
SOURCES = notify-send.sh notify-action.sh

PREFIX = /usr/local
BINDIR = $(PREFIX)/bin

PHONY: all
all: $(SOURCES)

install: all
	@mkdir -p $(BINDIR)
	@install -v -o root -m 755 $(SOURCES) $(BINDIR)

PHONY: uninstall
uninstall:
	@cd $(BINDIR) && rm -v $(SOURCES)
