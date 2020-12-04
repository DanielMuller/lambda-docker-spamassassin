ARG FUNCTION_DIR="/home/app/"
ARG RUNTIME_VERSION="3.9"
ARG DISTRO_VERSION="slim"
ARG DCC_VERSION=2.3.167
ARG DCC_SHA=e5da87aca80ddc8bc52fa93869576a2afaf0c1e563e3f97dee6e6531690fbad5
ARG DCC_BUILD_DIR="/opt/dcc"
ARG RIC_BUILD_DIR="/opt/ric"
ARG RIE_EXE="/opt/rie/aws-lambda-rie"
ARG SPAMD_VERSION=3.4.2-1+deb10u2
ARG SPAMD_UID=2022
ARG USERNAME=debian-spamd
ARG EXTRA_OPTIONS=--nouser-config
ARG PYZOR_SITE=public.pyzor.org:24441

FROM python:${RUNTIME_VERSION}-${DISTRO_VERSION}-buster AS python-buster
  ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC

# Build Image
FROM python-buster AS build-image
  RUN apt-get -yq update
  RUN apt-get -y --no-install-recommends install apt-utils
  RUN apt-get -y --no-install-recommends install \
      ca-certificates curl \
      gcc libc6-dev make \
      psutils \
      g++ \
      make \
      cmake \
      unzip \
      libcurl4-openssl-dev \
      autoconf \
      libtool

# Build DCC
FROM build-image AS dcc-build-image
  ARG DCC_VERSION
  ARG DCC_SHA
  ARG DCC_BUILD_DIR

  # Distributed Checksum Clearinghouse - requires a source-compile
  RUN cd /tmp && \
      curl -sLo dcc.tar.Z https://www.dcc-servers.net/dcc/source/old/dcc-$DCC_VERSION.tar.Z && \
      echo "$DCC_SHA  dcc.tar.Z" > checksums && \
      sha256sum -c checksums && \
      tar xzf dcc.tar.Z && \
      cd /tmp/dcc-$DCC_VERSION && \
      mkdir -p $DCC_BUILD_DIR && \
      ./configure -with-installroot=$DCC_BUILD_DIR && \
      make install && \
      sed -i 's/DCCIFD_ENABLE=off/DCCIFD_ENABLE=on/' $DCC_BUILD_DIR/var/dcc/dcc_conf && \
      chmod -R +rX $DCC_BUILD_DIR

FROM build-image as lambda-build-image
  ARG RIC_BUILD_DIR
  ARG RIE_EXE
  
  RUN mkdir -p ${RIC_BUILD_DIR}
  RUN mkdir -p $(dirname ${RIE_EXE})

  RUN python${RUNTIME_VERSION} -m pip install awslambdaric --target ${RIC_BUILD_DIR}
  ADD https://github.com/aws/aws-lambda-runtime-interface-emulator/releases/latest/download/aws-lambda-rie ${RIE_EXE}

FROM python-buster AS spamassassin-buster
  ARG SPAMD_VERSION
  ARG SPAMD_UID
  ARG USERNAME
  ARG DCC_BUILD_DIR
  ARG PYZOR_SITE

  # DCC is too much headache to run inside lambda (ro filesystem)
  # COPY --from=dcc-build-image ${DCC_BUILD_DIR}/usr/local/bin/ /usr/local/bin/
  # COPY --from=dcc-build-image ${DCC_BUILD_DIR}/var/dcc/ /var/dcc/

  RUN apt-get -yq update && \
    apt-get -yq --no-install-recommends install \
    pyzor razor spamassassin=$SPAMD_VERSION \
    gpg gpg-agent && \
    usermod --uid $SPAMD_UID $USERNAME && \
    mv /etc/mail/spamassassin/local.cf /etc/mail/spamassassin/local.cf-dist && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/log/* && \
    sed -i 's/^logfile = .*$/logfile = \/dev\/stderr/g' /etc/razor/razor-agent.conf
  # RUN sed -i '/^#\s*loadplugin .\+::DCC/s/^#\s*//g' /etc/spamassassin/v310.pre
    # echo "use_dcc 1" > /etc/mail/spamassassin/local.cf && \
    # echo "dcc_home /tmp/var/dcc" >> /etc/mail/spamassassin/local.cf && \
    # echo "dcc_timeout 8" >> /etc/mail/spamassassin/local.cf

  RUN chown -R $USERNAME /var/lib/spamassassin && \
    su $USERNAME bash -c "\
      cd ~$USERNAME && \
      mkdir -p .razor .spamassassin .pyzor && \
      razor-admin -discover && \
      razor-admin -create -conf=razor-agent.conf && \
      razor-admin -register -l && \
      echo $PYZOR_SITE > .pyzor/servers && \
      chmod g-rx,o-rx .pyzor .pyzor/servers"
  RUN mkdir -p /etc/spamassassin/sa-update-keys && \
    chmod 700 /etc/spamassassin/sa-update-keys && \
    chown debian-spamd:debian-spamd /etc/spamassassin/sa-update-keys && \
    chown -R debian-spamd:debian-spamd /var/lib/spamassassin/.pyzor
  RUN su $USERNAME bash -c "\
    /usr/bin/sa-update && \
    /usr/bin/sa-update --nogpg --channel sa.zmi.at"

FROM spamassassin-buster AS lambda-spamassassin
  ARG FUNCTION_DIR
  ARG RIC_BUILD_DIR
  ARG RIE_EXE

  RUN mkdir -p ${FUNCTION_DIR}

  COPY --from=lambda-build-image ${RIC_BUILD_DIR} ${FUNCTION_DIR}
  COPY --from=lambda-build-image ${RIE_EXE} /usr/local/bin/aws-lambda-rie
  RUN chmod 755 /usr/local/bin/aws-lambda-rie
  COPY app/main.py ${FUNCTION_DIR}/

  WORKDIR ${FUNCTION_DIR}

  COPY entry.sh /entry.sh
  RUN chmod 755 /entry.sh

  ENTRYPOINT [ "/entry.sh" ]
  CMD [ "main.handler" ]
