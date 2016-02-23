INSTALL_PATH?=/user/local/bin/show-volume.native

all: show-volume.ml
	corebuild -use-ocamlfind -pkgs lwt.unix,lwt,camomile,humane_re,textutils,yojson show-volume.native

clean:
	ocamlbuild -clean
	rm ./show-volume.native

install:
	cp show-volume.native $(INSTALL_PATH)

uninstall:
	rm $(INSTALL_PATH)
