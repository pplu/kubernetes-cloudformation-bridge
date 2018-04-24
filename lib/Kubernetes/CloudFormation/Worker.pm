package Kubernetes::CloudFormation::Worker {
  our $VERSION = '0.01';
  use Moose;
  with 'SQS::Worker', 'SQS::Worker::CloudFormationResource';

  use IPC::Open3;

  has kubectl => (is => 'ro', isa => 'Str', default => 'kubectl');

  sub send_command {
    my ($self, $command, $input) = @_;
    
    my ($in, $out, $err);
    my $pid = open3($in, $out, $err, $self->kubectl, $command, '-f', '-');
    print $in $input if (defined $input);
    close $in;
    my $output = join '', <$out>;

    waitpid( $pid, 0 );
    my $rc = $? >> 8;

    die "Error from kubernetes: $output" if ($rc != 0);
    return $output;
  }

  sub create_resource {
    my ($self, $request, $response) = @_;
    $self->send_command('create -f -');

  }

  sub update_resource {
    my ($self, $request, $response) = @_;
    $self->send_command('apply', ...);

  }

  sub delete_resource {
    my ($self, $request, $response) = @_;

  } 

  __PACKAGE__->meta->make_immutable;
}
1;

=head1 NAME

Kubernetes::CloudFormation::Worker - Create kubernetes resources from your CloudFormation templates

=head1 DESCRIPTION

This is the implementation of the worker that creates, updates and deletes resources from a kubernetes cluster
when commanded so from AWS CloudFormation.

=head1 USAGE

This class shouldn't be loaded directly. See the projects README for information about how to set up your kubernetes
cluster and use CloudFormation to create resources in the cluster.

=head1 COPYRIGHT and LICENSE

Copyright (c) 2018 by CAPSiDE

This code is distributed under the Apache 2 License. The full text of the license can be found in the LICENSE file included with this module.

=head1 AUTHORS

  Jose Luis Martinez
  JLMARTIN
  jlmartinez@capside.com

=cut
