
name = notice
src = $(name).sh

PREFIX = /usr/local
BINDIR = $(PREFIX)/bin

PHONY: all
all: $(src)

install: all
	@mkdir -p $(BINDIR)
	@install -v -o root -m 755 $(src) $(BINDIR)/$(name)

PHONY: uninstall
uninstall:
	@rm -v $(BINDIR)/$(name)
