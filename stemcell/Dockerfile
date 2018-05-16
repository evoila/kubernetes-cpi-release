FROM scratch

ADD  build/image.tgz /

RUN mkdir /startup && mv /var/vcap/* /startup
COPY build/bosh-agent /startup/bosh/bin/
COPY assets/agent.json /startup/bosh/
COPY assets/bosh-start-logging-and-auditing /startup/bosh/bin/
COPY runsvdir-start /usr/sbin

RUN rm -rf /warden-cpi-dev && /bin/echo -e "\numount /etc/resolv.conf >/dev/null 2>&1 || true" >> /startup/bosh/bin/bosh-agent-rc && /bin/echo -e "\numount /etc/hosts >/dev/null 2>&1 || true" >> /startup/bosh/bin/bosh-agent-rc
