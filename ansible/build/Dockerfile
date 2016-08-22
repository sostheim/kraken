FROM phusion/baseimage

RUN apt-get update \
    && apt-get install -y \
      ca-certificates \
      git \
      libffi-dev \
      libssl-dev \
      python \
      python-dev \
      python-pip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# python dependencies
COPY ./requirements.txt /tmp/requirements.txt
RUN pip install --upgrade --requirement /tmp/requirements.txt \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ENV ANSIBLE_CONFIG=/etc/ansible-config/ansible.cfg
COPY ansible.cfg $ANSIBLE_CONFIG

CMD ["/sbin/my_init"]
