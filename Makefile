PREFIX?= /usr/local
BINDIR?= ${PREFIX}/bin
MANDIR?= ${PREFIX}/share/man
INSTALL?= install
INSTALLDIR= ${INSTALL} -d
INSTALLBIN= ${INSTALL} -m 755

all: test

uninstall:
	rm -f ${DESTDIR}${BINDIR}/fasd
	rm -f ${DESTDIR}${MANDIR}/man1/fasd.1 # installed by older versions

install:
	${INSTALLDIR} ${DESTDIR}${BINDIR}
	${INSTALLBIN} fasd ${DESTDIR}${BINDIR}

# make test          run all tests
# make test T=name   run test/name.test.zsh only
test:
	zsh -n fasd
	zsh -f test/run.zsh $(T)

.PHONY: all install uninstall test
