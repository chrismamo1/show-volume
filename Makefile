all: show-volume.ml
	corebuild -package humane_re -package textutils -package yojson show-volume.native

install:
	cp show-volume.native /usr/local/bin/show-volume.native

uninstall:
	rm /usr/local/bin/show-volume.native
