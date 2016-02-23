INSTALL_PATH?=/usr/local/bin/show-volume.native

all: show-volume.native

show-volume.native: show-volume.ml
	corebuild -use-ocamlfind -pkgs lwt.unix,lwt,camomile,humane_re,textutils,yojson show-volume.native

clean:
	ocamlbuild -clean

install: show-volume.native
	cp show-volume.native $(INSTALL_PATH)

uninstall:
	rm $(INSTALL_PATH)
