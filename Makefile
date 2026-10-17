PREFIX ?= /usr/local
SBINDIR ?= $(PREFIX)/sbin
UNITDIR ?= /etc/systemd/system

.PHONY: install uninstall

install:
	install -Dm755 wsl-quickack $(DESTDIR)$(SBINDIR)/wsl-quickack
	install -d $(DESTDIR)$(UNITDIR)
	sed 's|@SBINDIR@|$(SBINDIR)|' wsl-quickack.service > $(DESTDIR)$(UNITDIR)/wsl-quickack.service
	chmod 644 $(DESTDIR)$(UNITDIR)/wsl-quickack.service

uninstall:
	rm -f $(DESTDIR)$(SBINDIR)/wsl-quickack $(DESTDIR)$(UNITDIR)/wsl-quickack.service
