BINDIR := /usr/local/bin
SCRIPTDIR := $(HOME)/Library/Scripts
SUDO ?= sudo

.PHONY: all clean install uninstall

all: vo-ignore

vo-ignore: vo-ignore.swift
	swiftc -O -o vo-ignore vo-ignore.swift

clean:
	rm -f vo-ignore

install: vo-ignore
	$(SUDO) install -d "$(BINDIR)"
	$(SUDO) install -m 755 vo-ignore "$(BINDIR)/vo-ignore"
	install -d "$(SCRIPTDIR)"
	install -m 644 vo-ignore.scpt "$(SCRIPTDIR)/vo-ignore.scpt"

uninstall:
	$(SUDO) rm -f "$(BINDIR)/vo-ignore"
	rm -f "$(SCRIPTDIR)/vo-ignore.scpt"
