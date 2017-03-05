CFLAGS=-std=gnu99 -static -m64 -fno-PIC -nostdlib -nodefaultlibs -fno-stack-protector -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -masm=intel -O1 -g -c

#.PHONY: musl

default: #musl lua libsqlite3.a liblsqlite3.a
	./musl-custom-gcc $(CFLAGS) src/init.S -o bin/initS.o
	@# not sure why this has to be gcc instead of musl-gcc
	@# trap on lgdt if musl-gcc
	@# perhaps this is because musl is 64 bit but I pass -m32
	gcc $(CFLAGS) -m32 src/init.c -o bin/init.o
	@# init code is executed in protected mode, but is linked with 64-bit code
	objcopy -I elf32-i386 -O elf64-x86-64 bin/init.o bin/init.o
	@#~ luac -o luakernel.luac luakernel.lua
	@#~ xxd -i luakernel.luac luakernel.luac.h
	cd src && ../generate-lua-bundle.sh
	./musl-custom-gcc $(CFLAGS) -Idep/lua-5.2.3/src -Idep/sqlite3 src/luakernel.c -fno-stack-protector -o bin/luakernel.o
	./musl-custom-gcc -L. -T link.ld -fno-PIC -static -z max-page-size=0x1000 \
	  -o bin/luakernel.elf bin/initS.o bin/init.o bin/luakernel.o \
	  dep/lua-5.2.3/src/liblua.a #libsqlite3.a liblsqlite3.a
	# make bootable ISO using GRUB
	rm -f bin/luakernel.iso bin/*.o
	@# comment out when debugging with gdb -- uncomment to get under 1.44 MB
	@#strip bin/luakernel.elf
	mkdir -p bin/boot/grub/
	cp grub.cfg bin/boot/grub
	@#pkgdatadir='~/scratch/grub/grub-core' ~/scratch/grub/grub-mkrescue -d /home/ers/scratch/grub/grub-core --locale-dir=/usr/lib/locale -o bin/luakernel.iso bin #-v
	grub-mkrescue bin --fonts= \
	  --install-modules="normal multiboot2 part_acorn part_amiga part_apple part_bsd part_dfly part_dvh part_gpt part_msdos part_plan part_sun part_sunpc" \
	  --locales= -o bin/luakernel.iso #-verbose

musl:
	cd dep/musl && ./configure --disable-shared --enable-debug && make -j5

lua:
	cd dep/lua-5.2.3 && make -j5 LDFLAGS="-m64 -fno-PIC" CC="gcc -m64 -O0 -g -fno-stack-protector -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -fno-PIC -static" ansi

libsqlite3.a:
	gcc $(CFLAGS) -static -DSQLITE_ENABLE_MEMSYS5=1 -DSQLITE_THREADSAFE=0 dep/sqlite3/sqlite3.c -o libsqlite3.a
	
liblsqlite3.a:
	gcc -c $(CFLAGS) -Idep/lua-5.2.3/src/ -Idep/sqlite3 -static dep/lsqlite3.c -o liblsqlite3.a

run: default
	kvm -m 1024 -boot d -vga vmware -cdrom bin/luakernel.iso
	#qemu-system-x86_64 -kernel bin/luakernel.elf
	#~/scratch/bochs-2.6.6/bochs -f bochsrc.txt -q

dump:
	objdump -S -M intel -d bin/luakernel.elf | less
	
dumpdata:
	objdump -M intel -D bin/luakernel.elf | less

debug: default
	#kvm -s -m 1024 -boot d -vga vmware -cdrom bin/luakernel.iso
	#qemu-system-x86_64 -boot d -cdrom bin/luakernel.iso -s -S
	bochs-gdb-debugger -f bochsrc.txt -q
	#bochs-gui-debugger -f bochsrc.txt -q
	
gdb:
	#gdb -ex "set remote target-features-packet on" -ex "target remote localhost:1234" \
	#-ex "set architecture i386:x86-64:intel" bin/luakernel.elf
	
	#-ex "break trap" -ex "break resume_error" -ex "break luaG_runerror"
	
	gdb -ex "target remote localhost:1234" -ex "set remote target-features-packet on" \
	-ex "set architecture i386:x86-64:intel" \
	-ex "set disassembly-flavor intel" -ex "layout split" -ex "set confirm off" \
	-ex "break trap" \
	bin/luakernel.elf
	
	# p g->strt.size
	# p g->strt.hash[h % g->strt.size]
	# p *g->strt.hash@32
	# dump 32 quad words of string hash table
	# x /32xg 0x623710
	
	#-ex 'break internshrstr if str == 0x11b039' \
	
	#-ex 'break internshrstr if strcmp(str, "__gc") == 0' \
	
	# layout src
	# layout reg
	# layout asm
	# layout split
	
	# ctrl+x o to switch window focus for scrolling up in the command history

	#nemiver --remote=localhost:1234 --gdb-binary=/usr/bin/gdb bin/luakernel.elf
	#ddd --eval-command="target remote localhost:1234"

clean:
	#rm -f bin/*
