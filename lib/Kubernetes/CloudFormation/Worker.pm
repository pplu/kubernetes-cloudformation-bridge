package KubeCtl::Result {
  use Moose;
  has output => (is => 'ro', isa => 'Str');
  has rc => (is => 'ro', isa => 'Int', required => 1);
  
  has success => (is => 'ro', isa => 'Bool', lazy => 1, default => sub {
    my $self = shift;
    return $self->rc == 0;
  });
}
package Kubernetes::CloudFormation::Worker {
  our $VERSION = '0.01';
  use Moose;
  with 'SQS::Worker', 'SQS::Worker::SNS', 'SQS::Worker::CloudFormationResource';

  use JSON::MaybeXS;

  use IPC::Open3;

  has _json => (is => 'ro', default => sub {
    my $self = shift;
    JSON::MaybeXS->new;
  });

  has kubectl => (is => 'ro', isa => 'Str', default => 'kubectl');

  sub send_command {
    my ($self, $input, @kubectl_params) = @_;
    
    my ($in, $out, $err);
    my $pid = open3($in, $out, $err, $self->kubectl, @kubectl_params);
    print $in $input if (defined $input);
    close $in;
    my $output = join '', <$out>;

    waitpid( $pid, 0 );
    my $rc = $? >> 8;

    return KubeCtl::Result->new(
      rc => $rc,
      output => $output
    );
  }

  sub create_resource {
    my ($self, $request, $response) = @_;

    my $json = $self->_json->encode($request->ResourceProperties);
    my $result = $self->send_command($json, 'create', '-f', '-');
    if (not $result->success) {
      $response->Status('FAILED');
      $response->Reason($result->output);
      die "Failed " . $result->output;
    } else {
      $response->Status('SUCCESS');
      #$response->Data({ });
    }
    print Dumper($response);
  }

  sub update_resource {
    my ($self, $request, $response) = @_;
    #$self->send_command('apply', ...);
  }

  sub delete_resource {
    my ($self, $request, $response) = @_;

    my $result = $self->send_command(undef, 'delete', $request->PhysicalResourceId);
    if (not $result->success) {
      $response->Status('FAILED');
      $response->Reason($result->output);
    } else {
      $response->Status('SUCCESS');
      #$response->Data({ });
    }
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
