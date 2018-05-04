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

  use IPC::Open3;

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

  use IO::K8s;

  our $cf_type = {
    'Custom::KubernetesService' => {
      kind => 'Service',
      params_class => 'IO::K8s::Api::Core::V1::Service',
    },
  };

  sub create_resource {
    my ($self, $request, $response) = @_;

    my $k8s_info = $cf_type->{ $request->ResourceType };

    # TODO: this should be transmitted to the user
    die "Unknown resource type " . $request->ResourceType if (not defined $k8s_info);

    my $k8s = IO::K8s->new;
    my $object = $k8s->struct_to_object($k8s_info->{ params_class }, $request->ResourceProperties);

    # TODO: validate kind
    my $name = $object->metadata->name;

    my $json = $k8s->object_to_json($object);
    my $result = $self->send_command($json, 'create', '-f', '-');

    my $id = $self->make_physical_resource_id($k8s_info->{ kind }, '0000-0000-00000000000000000000', $name);

    if (not $result->success) {
      $response->Status('FAILED');
      $response->Reason($result->output);
    } else {
      $response->PhysicalResourceId($id);
      $response->Status('SUCCESS');
      $response->Data({
        Name => $name,
      });
    }
  }

  sub update_resource {
    my ($self, $request, $response) = @_;
    #$self->send_command('apply', ...);
  }

  sub make_physical_resource_id {
    my ($self, $type, $uid, $name) = @_;
    return join '|', $type, $uid, $name;
  }

  sub split_physical_resource_id {
    my ($self, $resource_id) = @_;
    my @parts = split /\|/, $resource_id;
    die "Got an unexpected number of parts from $resource_id" if (@parts != 3);
    return @parts;
  }

  sub delete_resource {
    my ($self, $request, $response) = @_;

    my ($type, $uid, $name) = $self->split_physical_resource_id($request->PhysicalResourceId);
    my $result = $self->send_command(undef, 'delete', $type, $name);
    if (not $result->success) {
      $response->Status('FAILED');
      $response->Reason($result->output);
    } else {
      $response->Status('SUCCESS');
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
