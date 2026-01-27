PREFIX ?= /usr/local

install:
	@mkdir -p $(PREFIX)/bin
	ln -sf $(CURDIR)/bin/throwback $(PREFIX)/bin/throwback
	@echo "Installed: $(PREFIX)/bin/throwback -> $(CURDIR)/bin/throwback"

uninstall:
	rm -f $(PREFIX)/bin/throwback
	@echo "Removed: $(PREFIX)/bin/throwback"

.PHONY: install uninstall
