FROM alpine:3.13.6 AS build
MAINTAINER docker@chabs.name

ENV AMULE_VERSION 2.3.3
ENV UPNP_VERSION 1.14.7
ENV CRYPTOPP_VERSION CRYPTOPP_8_5_0
ARG BOOST_VERSION=1.77.0
ARG BOOST_DIR=boost_1_77_0
ENV BOOST_VERSION ${BOOST_VERSION}
ENV CFLAGS="-lstdc++"

RUN apk --update add gd geoip libpng libwebp pwgen sudo expat wxgtk3 libgcc libstdc++ musl zlib bash && \
    apk --update add --virtual build-dependencies alpine-sdk automake openssl  linux-headers build-base \
                               autoconf=2.69-r3 bison g++ gcc gd-dev geoip-dev \
                               gettext gettext-dev git libpng-dev libwebp-dev \
                               libtool libsm-dev make musl-dev wget \
                               zlib-dev wxgtk3 wxgtk-dev
# Build libupnp
RUN mkdir -p /opt \
    && cd /opt \
    && wget "http://downloads.sourceforge.net/sourceforge/pupnp/libupnp-${UPNP_VERSION}.tar.bz2" \
    && tar xvfj libupnp*.tar.bz2 \
    && cd libupnp* \
    && ./configure --prefix=/usr \
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && make install
# Build boost
RUN cd /opt \
    && wget http://downloads.sourceforge.net/project/boost/boost/${BOOST_VERSION}/${BOOST_DIR}.tar.bz2 \
    && tar --bzip2 -xf ${BOOST_DIR}.tar.bz2 \
    && cd ${BOOST_DIR} \
    && ./bootstrap.sh \
    && ./b2 --prefix=/usr -j 4 link=shared runtime-link=shared install
# Build crypto++
RUN mkdir -p /opt && cd /opt \
    && git clone --branch ${CRYPTOPP_VERSION} --single-branch "https://github.com/weidai11/cryptopp" /opt/cryptopp \
    && cd /opt/cryptopp \
    && sed -i -e 's/^CXXFLAGS/#CXXFLAGS/' GNUmakefile \
    && export CXXFLAGS="${CXXFLAGS} -DNDEBUG -fPIC" \
    && make -f GNUmakefile \
    && make libcryptopp.so \
    && install -Dm644 libcryptopp.so* /usr/lib/ \
    && mkdir -p /usr/include/cryptopp \
    && install -m644 *.h /usr/include/cryptopp/

# Build amule from source
RUN mkdir -p /opt/amule \
    && git clone --branch ${AMULE_VERSION} --single-branch "https://github.com/amule-project/amule" /opt/amule \
    && cd /opt/amule \
    && ./autogen.sh \
    && ./configure \
        --disable-gui \
        --disable-amule-gui \
        --disable-wxcas \
        --disable-alc \
        --disable-plasmamule \
        --disable-kde-in-home \
        --prefix=/usr \
        --mandir=/usr/share/man \
        --enable-unicode \
        --without-subdirs \
        --without-expat \
		--with-boost \
        --enable-amule-daemon \
        --enable-amulecmd \
        --enable-webserver \
        --enable-cas \
        --enable-alcc \
        --enable-fileview \
        --enable-geoip \
        --enable-mmap \
        --enable-optimize \
        --enable-upnp \
        --disable-debug \
    && make -j$(getconf _NPROCESSORS_ONLN) \
    && make install
# Final cleanup
RUN rm -rf /var/cache/apk/* && rm -rf /opt \
    && apk del build-dependencies \
    && cd /usr \
    && tar -cvf usr.tar ./*
	

FROM alpine:3.13.6
COPY --from=build /usr/usr.tar /usr/
# Install a nicer web ui
RUN apk --update add git bash sudo\
    && cd /usr \
    && tar -xvf usr.tar \
    && rm -rf usr.tar \
    && cd /usr/share/amule/webserver \
    && git clone https://github.com/MatteoRagni/AmuleWebUI-Reloaded \
    && rm -rf AmuleWebUI-Reloaded/.git AmuleWebUI-Reloaded/doc-images

# Add startup script
ADD amule.sh /home/amule/amule.sh
RUN chmod a+x /home/amule/amule.sh

EXPOSE 4711/tcp 4712/tcp 4672/udp 4665/udp 4662/tcp 4661/tcp

ENTRYPOINT ["/home/amule/amule.sh"]
