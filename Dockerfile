FROM registry.access.redhat.com/rhscl/httpd-24-rhel7:latest

ENV HTTPD_ROOT_DIR=/opt/rh/httpd24/root
ENV HTTPD_BIN_DIR=${HTTPD_ROOT_DIR}/usr/local/bin \
    HTTP_REPO_ROOT=/home/git/data/gls \
    PLATFORM_DOCUMENT_ROOT=${HTTPD_ROOT_DIR}/opt/feedhenry \
    REPO_FOLDER_NAME=repositories \
    HTTPD_LOG_LEVEL=INFO \
    HTTPD_GIT_PORT=8000 \
    HTTPD_PROXY_PORT=8010 \
    MILLICORE_HTTP_HOST=example.com

ADD httpd/root/usr ${HTTPD_ROOT_DIR}/usr
ADD httpd/root/var/rpm /var/rpm
COPY httpd/root/etc/httpd/conf.d/*.conf /etc/httpd/conf.d/

RUN yum-config-manager --enable rhel-server-rhscl-7-rpms && \
    yum-config-manager --enable rhel-7-server-optional-rpms && \
    yum-config-manager --enable rhel-7-server-ose-3.0-rpms && \
    INSTALL_PKGS="openssh-server ed libicu-devel rh-ruby23 rh-ruby23-ruby-devel rh-ruby23-rubygem-rake rh-ruby23-rubygem-bundler rh-nodejs4" && \
    yum install -y --setopt=tsflags=nodocs $INSTALL_PKGS && rpm -V $INSTALL_PKGS && \
    yum clean all -y

USER root
# sshd
RUN ["bash", "-c", "sshd-keygen && \
     mkdir /var/run/sshd"]

RUN stat /var/rpm/rhmap-mod_authnz_external-3.3.1-7.el7map.x86_64.rpm && \
    rpm -Uvh  /var/rpm/rhmap-mod_authnz_external-3.3.1-7.el7map.x86_64.rpm

# add a user that id a member of the root group. we will replace later with the user assigned to the pod. Change perms to allow the root group to modify and use files as needed. These changes allow the pod assigned user to be part of the root group and have a real uid assigned
RUN adduser --system -s /bin/bash -u 1234321 -g 0 git && \ 
   chown root:root /etc/ssh/* /home && \
   chmod 775 /etc/ssh /home && \  
   chmod 660 /etc/ssh/sshd_config && \
   chmod 664 /etc/passwd /etc/group && \
   chmod 775 /var/run && \
   mkdir -p /home/git/data/gls && \
   chmod -R 775 /home/git && \
   chmod -R 775 /opt/app-root && \
   chmod 775 -R /var/log/httpd24 && \
   ls -al /var/log && \
   chmod -Rf +rx ${HTTPD_BIN_DIR}/ && \
   chmod -R 775 /opt/rh/httpd24/root/usr/local && \
   chmod -R 775 /opt/rh/httpd24/root/etc/httpd && \
   chown -Rf root:0 /opt/rh/httpd24/root/usr/local && \
   chown -R root:0 /opt/rh/httpd24/root/etc/httpd && \
   chown -Rf root:0 ${HTTPD_ROOT_DIR}/var/www/html/ && \
   mkdir -p $HTTP_REPO_ROOT/$REPO_FOLDER_NAME

EXPOSE 2022

# gitlab-shell setup
USER root
COPY . /home/git/gitlab-shell
WORKDIR /home/git/gitlab-shell
RUN ["bash", "-c", "bundle"]
RUN mkdir /home/git/gitlab-config && \
    ## Setup default config placeholder
    cp config.yml.example ../gitlab-config/config.yml
    # PAM workarounds for docker and public key auth

RUN sed -i \
          # Disable processing of user uid. See: https://gitlab.com/gitlab-org/gitlab-ce/issues/3027
          -e "s|session\s*required\s*pam_loginuid.so|session optional pam_loginuid.so|g" \
          # Allow non root users to login: http://man7.org/linux/man-pages/man8/pam_nologin.8.html
          -e "s|account\s*required\s*pam_nologin.so|#account optional pam_nologin.so|g" \
          /etc/pam.d/sshd
    # Security recommendations for sshd
RUN sed -i \
          -e "s|^[#]*GSSAPIAuthentication yes|GSSAPIAuthentication no|" \
          -e 's/#UsePrivilegeSeparation.*$/UsePrivilegeSeparation no/' \
          -e 's/#Port.*$/Port 2022/' \
          -e "s|^[#]*ChallengeResponseAuthentication no|ChallengeResponseAuthentication no|" \
          -e "s|^[#]*PasswordAuthentication yes|PasswordAuthentication no|" \
          -e "s|^[#]*StrictModes yes|StrictModes no|" \
          /etc/ssh/sshd_config && \
    echo -e "UseDNS no \nAuthenticationMethods publickey" >> /etc/ssh/sshd_config

RUN rm -f /run/nologin && \
    ln -s /home/git/gitlab-config/config.yml && \
    chmod -R 775 /home/git

USER git

CMD echo -e ",s/1234321/`id -u`/g\\012 w" | ed -s /etc/passwd && ssh-keygen -A && bin/start.sh
