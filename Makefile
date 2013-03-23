# these can (and should) be overridden on the make command line for production
CFLAGS :=  -g -Wall -O2
# If your dynamic linker (uClibc's ld.so, for example) does not support symbol
# versioning, override this to '0'
#SYMVERS_ENABLED := 1
# these are used for the benchmarks in addition to the normal CFLAGS.
# Normally no need to overwrite unless you find a new magic flag to make
# STREAM run faster.
BENCH_CFLAGS := -O3 -ffast-math -funroll-loops

ALL_CFLAGS += $(CFLAGS) -I.

try-run = $(shell set -e;	\
	TMP=".$$$$.tmp";	\
	TMPO=".$$$$.o";		\
	if ($(1)) >/dev/null 2>&1; \
	then echo "$(2)";	\
	else echo "$(3)";	\
	fi;			\
	rm -f "$$TMP" "$$TMPO")

cc-can-build = $(call try-run,\
	printf "%s\n" "$(1)" | $(CC) $(ALL_CFLAGS) -c -x c - -o "$$TMP",$(2),$(3))
cc-option = $(call try-run,\
	$(CC) $(ALL_CFLAGS) $(1) -c -x c /dev/null -o "$$TMP",$(1),$(2))

# find out if compiler supports __thread
ifeq ($(call cc-can-build,int __thread x;,yes,no),no)
	ALL_CFLAGS += -D__thread=""
endif

ifndef SYMVERS_ENABLED
define SYMVERS-test
#include <dlfcn.h>
int main(void) { dlvsym(NULL,NULL,NULL); return 0}
endef
SYMVERS_ENABLED=$(call cc-can-build,$(SYMVERS-test),1,0)
endif


# find out if compiler supports -ftree-vectorize
BENCH_CFLAGS += $(call cc-option,-ftree-vectorize)

TOOLS := numactl numademo memhog numamon stream migratepages migspeed \
	numastat threadtest
TESTS := pagesize tshared mynode ftok prefered randmap nodemap distance \
	tbitmap mbind_mig_pages migrate_pages move_pages \
	realloc_test node-parse
TESTS := $(addprefix test/,$(TESTS))

libobj-numa = libnuma.o syscall.o distance.o sysfs.o affinity.o rtnetlink.o
LIBNUMA_VER=1

CLEANFILES := $(libobj-numa) numactl.o numademo.o \
	      libnuma.so libnuma.so.$(LIBNUMA_VER) numamon.o bitops.o \
	      memhog.o util.o stream_main.o stream_lib.o shm.o clearcache.o \
	      test/mynode.o test/tshared.o mt.o empty.o empty.c \
	      migspeed.o libnuma.a \
	      test/A test/after test/before\
	      $(TOOLS) $(TESTS)
SOURCES := bitops.c libnuma.c distance.c memhog.c numactl.c numademo.c \
	numamon.c shm.c stream_lib.c stream_main.c syscall.c util.c mt.c \
	clearcache.c test/*.c affinity.c sysfs.c rtnetlink.c

ifeq ($(strip $(PREFIX)),)
prefix := /usr
else
prefix := $(PREFIX)
endif
libdir := $(prefix)/lib
docdir := $(prefix)/share/doc

all: $(TOOLS) $(TESTS) libnuma.so libnuma.a

numactl: numactl.o util.o shm.o bitops.o

numastat: ALL_CFLAGS += -std=gnu99
numastat: numastat.o

migratepages: migratepages.c util.o bitops.o

migspeed: LDLIBS += -lrt
migspeed: migspeed.o util.o

memhog: util.o memhog.o

numademo: LDLIBS += -lm
# GNU make 3.80 appends BENCH_CFLAGS twice. Bug? It's harmless though.
numademo: ALL_CFLAGS += -DHAVE_STREAM_LIB -DHAVE_MT -DHAVE_CLEAR_CACHE $(BENCH_CFLAGS)
stream_lib.o: ALL_CFLAGS += $(BENCH_CFLAGS)
mt.o: ALL_CFLAGS += $(BENCH_CFLAGS)
numademo: numademo.o stream_lib.o mt.o clearcache.o

test_numademo: numademo
	LD_LIBRARY_PATH=$$(pwd) ./numademo -t -e 10M

numamon: numamon.o
threadtest: threadtest.o

stream: LDLIBS += -lm
stream: stream_lib.o stream_main.o util.o

LIB_CFLAGS = -fPIC
version-map-numa = versions.ldscript
version-ldflags-numa = -Wl,--version-script,$(version-map-numa)
ifeq ($(SYMVERS_ENABLED),1)
LIB_CFLAGS += -DSYMVERS_ENABLED=1
endif
libnuma.so.$(LIBNUMA_VER): $(libobj-numa) $(version-map-numa)
	$(CC) $(LDFLAGS) -shared -Wl,-soname=$@ $(version-ldflags-numa) -Wl,-init,numa_init -Wl,-fini,numa_fini -o $@ $(filter-out $(version-map-numa),$^)

%.so: %.so.$(LIBNUMA_VER)
	ln -sf $< $@

obj-to-dep = $(dir $1).$(notdir $1).d
lib-flags = $(if $(filter $1,$(libobj-numa)),$(LIB_CFLAGS))

%.o : %.c
	$(CC) $(ALL_CFLAGS) -o $@ -c $< -MMD -MF $(call obj-to-dep,$@) $(call lib-flags,$@)

$(TOOLS) $(TESTS) : libnuma.so libnuma.a
	$(CC) $(LDFLAGS) -o $@ $(filter-out libnuma.so,$(filter-out libnuma.a,$^)) $(LDLIBS) -L. -lnuma

AR ?= ar
RANLIB ?= ranlib
libnuma.a: $(libobj-numa)
	$(AR) rc $@ $^
	$(RANLIB) $@

test/tshared : test/tshared.o
test/mynode  : test/mynode.o
test/pagesize: test/pagesize.o
test/prefered: test/prefered.o
test/ftok    : test/ftok.o
test/randmap : test/randmap.o
test/nodemap : test/nodemap.o
test/distance: test/distance.o
test/tbitmap : test/tbitmap.o
test/move_pages: test/move_pages.o
test/mbind_mig_pages: test/mbind_mig_pages.o
test/migrate_pages: test/migrate_pages.o
test/realloc_test: test/realloc_test.o
test/node-parse: test/node-parse.o util.o

.PHONY: install all clean html

MANPAGES := numa.3 numactl.8 numastat.8 migratepages.8 migspeed.8

install: numactl migratepages migspeed numademo.c numamon memhog libnuma.so.$(LIBNUMA_VER) numa.h numaif.h numacompat1.h numastat $(MANPAGES)
	mkdir -p $(prefix)/bin
	install -m 0755 numactl $(prefix)/bin
	install -m 0755 migratepages $(prefix)/bin
	install -m 0755 migspeed $(prefix)/bin
	install -m 0755 numademo $(prefix)/bin
	install -m 0755 memhog $(prefix)/bin
	mkdir -p $(prefix)/share/man/man2 $(prefix)/share/man/man8 $(prefix)/share/man/man3
	install -m 0644 migspeed.8 $(prefix)/share/man/man8
	install -m 0644 migratepages.8 $(prefix)/share/man/man8
	install -m 0644 numactl.8 $(prefix)/share/man/man8
	install -m 0644 numastat.8 $(prefix)/share/man/man8
	install -m 0644 numa.3 $(prefix)/share/man/man3
	( cd $(prefix)/share/man/man3 ; for i in $$(./manlinks) ; do ln -sf numa.3 $$i.3 ; done )
	mkdir -p $(libdir)
	install -m 0755 libnuma.so.$(LIBNUMA_VER) $(libdir)
	cd $(libdir) ; ln -sf libnuma.so.$(LIBNUMA_VER) libnuma.so
	install -m 0644 libnuma.a $(libdir)
	mkdir -p $(prefix)/include
	install -m 0644 numa.h numaif.h numacompat1.h $(prefix)/include
	install -m 0755 numastat $(prefix)/bin
	if [ -d $(docdir) ] ; then \
		mkdir -p $(docdir)/numactl/examples ; \
		install -m 0644 numademo.c $(docdir)/numactl/examples ; \
	fi

HTML := html/numactl.html html/numa.html

clean:
	rm -f $(CLEANFILES)
	@rm -rf html

distclean: clean
	rm -f .[^.]* */.[^.]*
	rm -f *~ */*~ *.orig */*.orig */*.rej *.rej

html: $(HTML)

htmldir:
	if [ ! -d html ] ; then mkdir html ; fi

html/numactl.html: numactl.8 htmldir
	groff -Thtml -man numactl.8 > html/numactl.html

html/numa.html: numa.3 htmldir
	groff -Thtml -man numa.3 > html/numa.html

.PHONY: test regress1 regress2

regress1:
	cd test ; ./regress

regress2:
	cd test ; ./regress2

regress3:
	cd test ; ./regress-io

test: all regress1 regress2 test_numademo regress3

-include $(wildcard .*.d)
