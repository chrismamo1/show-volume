INSTALL_PATH?=/user/local/bin/show-volume.native

all: show-volume.ml
	corebuild -package humane_re -package textutils -package yojson show-volume.native

install:
	cp show-volume.native $(INSTALL_PATH)

uninstall:
	rm $(INSTALL_PATH)
