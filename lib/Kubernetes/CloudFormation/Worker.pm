package KubeCtl::Result {
  use Moose;
  use JSON::MaybeXS;
  has output => (is => 'ro', isa => 'Str');
  has rc => (is => 'ro', isa => 'Int', required => 1);
  has json => (is => 'ro', isa => 'HashRef', lazy => 1, default => sub {
    my $self = shift;
    return decode_json($self->output);
  });
  
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

  our $cf_type_to_kube_kind = {
    'Custom::KubernetesService' => 'Service'
  };
  our $kube_kind_to_kube_class = {
     'Service' => 'IO::K8s::Api::Core::V1::Service',
  };

  has _k8s => (is => 'ro', isa => 'IO::K8s', default => sub { IO::K8s->new });

  sub get_object_from_kubernetes {
    my ($self, $kind, $name) = @_;
    
    my $result = $self->send_command(undef, 'get', $kind, $name, '-o=json');
    if ($result->success) {
      return $self->_k8s->struct_to_object($kube_kind_to_kube_class->{ $kind }, $result->json);
    } else {
      return undef;
    }
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

  sub create_resource {
    my ($self, $request, $response) = @_;

    my $kube_kind = $cf_type_to_kube_kind->{ $request->ResourceType };
    my $kube_class = $kube_kind_to_kube_class->{ $kube_kind };

    # TODO: this should be transmitted to the user
    die "Unknown resource type " . $request->ResourceType if (not defined $kube_kind);

    my $object = $self->_k8s->struct_to_object($kube_class, $request->ResourceProperties);

    # TODO: validate kind
    my $name = $object->metadata->name;

    my $json = $self->_k8s->object_to_json($object);
    my $result = $self->send_command($json, 'create', '-f', '-');

    if (not $result->success) {
      $response->Status('FAILED');
      $response->Reason($result->output);
    } else {
      my $new_object = $self->get_object_from_kubernetes($kube_kind, $name);

      my $id = $self->make_physical_resource_id($kube_kind, $new_object->metadata->uid, $name);

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

  sub delete_resource {
    my ($self, $request, $response) = @_;

    my ($type, $uid, $name) = $self->split_physical_resource_id($request->PhysicalResourceId);

    if (my $object = $self->get_object_from_kubernetes($type, $name)) {
      if ($object->metadata->uid ne $uid) {
        $response->Status('FAILED');
        $response->Reason('Found object with a different Kubernetes UID than expected. Not deleting');
      } else {
        my $result = $self->send_command(undef, 'delete', $type, $name);
        if (not $result->success) {
          $response->Status('FAILED');
          $response->Reason($result->output);
        } else {
          $response->Status('SUCCESS');
        }
      }
    } else {
      $response->Status('FAILED');
      $response->Reason("Can't find $type with name $name and uid $uid for deletion");
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
