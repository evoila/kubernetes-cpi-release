FROM debian:stable
ENV PASSWORD root

RUN apt-get -y update
RUN apt-get -y install openssh-server
RUN mkdir /run/sshd && mkdir /home/jumphost && useradd jumphost && chsh -s /bin/bash jumphost

COPY entrypoint.sh /

CMD ["/entrypoint.sh"]