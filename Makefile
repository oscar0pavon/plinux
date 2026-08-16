plinux:
	./build.sh toolchain
	./build.sh chroot build
	./build.sh chroot packages
	./build.sh chroot cleanup
	./build.sh chroot strip
	./build.sh
	./build.sh virt
