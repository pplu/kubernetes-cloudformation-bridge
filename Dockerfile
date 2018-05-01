FROM perl:5.26
COPY cpanfile .
RUN cpanm -n -l local --installdeps .
COPY *.tar.gz ./
RUN cpanm -n -l local SQS-Worker-CloudFormationResource-0.01.tar.gz

FROM perl:5.26
RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.10.0/bin/linux/amd64/kubectl ; \
    chmod +x kubectl ; \
    mv kubectl /usr/local/bin/kubectl
RUN mkdir -p /root/local/bin
RUN mkdir -p /root/local/lib
COPY --from=0 /root/local/bin local/bin
COPY --from=0 /root/local/lib local/lib
ENV PATH=/root/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV PERL5LIB=/root/local/lib/perl5
COPY Kubernetes-CloudFormation-Worker-0.01.tar.gz .
RUN cpanm -n -l local Kubernetes-CloudFormation-Worker-0.01.tar.gz

ENTRYPOINT [ "spawn_worker", "--worker=Kubernetes::CloudFormation::Worker" ]
