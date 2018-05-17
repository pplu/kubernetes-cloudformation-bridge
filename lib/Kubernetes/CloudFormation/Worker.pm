package Kubernetes::CloudFormation::Worker {
  our $VERSION = '0.01';
  use Moose;
  with 'SQS::Worker', 'SQS::Worker::SNS', 'SQS::Worker::CloudFormationResource';

  use Kubectl::CLIWrapper;
  use IO::K8s;

  our $cf_type_to_kube_kind = {
    'Custom::KubernetesService' => 'Service',
    'Custom::KubernetesReplicaset' => 'ReplicaSet',
    'Custom::KubernetesDeployment' => 'Deployment',
  };
  our $kube_kind_to_kube_class = {
     'Service' => 'IO::K8s::Api::Core::V1::Service',
     'ReplicaSet', 'IO::K8s::Api::Apps::V1::ReplicaSet',
     'Deployment' => 'IO::K8s::Api::Extensions::V1beta1::Deployment',
  };

  has _k8s => (is => 'ro', isa => 'IO::K8s', default => sub { IO::K8s->new });
  has _kube => (is => 'ro', isa => 'Kubectl::CLIWrapper', default => sub { Kubectl::CLIWrapper->new });

  sub get_object_from_kubernetes {
    my ($self, $kind, $name) = @_;
    
    my $result = $self->_kube->json('get', $kind, $name);
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

    my $rp_hash = $request->ResourceProperties;

    if (not exists $rp_hash->{ kind }) {
      $rp_hash->{ kind } = $kube_kind;
    } elsif ($rp_hash->{ kind } ne $kube_kind) {
      $response->set_failed('The resource type and the kind of resource are not in sync');
      return;
    }

    if (not defined $rp_hash->{ metadata } or not defined $rp_hash->{ metadata }->{ name }) {
      $rp_hash->{ metadata }->{ generateName } = lc($request->LogicalResourceId) . '-';
    }

    my $object = $self->_k8s->struct_to_object($kube_class, $request->ResourceProperties);

    my $json = $self->_k8s->object_to_json($object);
    my $result = $self->_kube->input($json, 'create', '-f', '-');

    if (not $result->success) {
      $response->set_failed($result->output);
    } else {
      my ($name) = ($result->output =~ m/^.* "(.*)" created/);
      die "Couldn't get created object name from " . $result->output if (not defined $name);
      my $new_object = $self->get_object_from_kubernetes($kube_kind, $name);

      my $id = $self->make_physical_resource_id($kube_kind, $new_object->metadata->uid, $name);

      $response->PhysicalResourceId($id);
      $response->set_success;
      $response->Data({
        Name => $name,
      });
    }
  }

  sub update_resource {
    my ($self, $request, $response) = @_;
    #$self->_kube->input($json, 'apply', ...);
  }

  sub delete_resource {
    my ($self, $request, $response) = @_;

    my ($type, $uid, $name) = $self->split_physical_resource_id($request->PhysicalResourceId);

    if (my $object = $self->get_object_from_kubernetes($type, $name)) {
      if ($object->metadata->uid ne $uid) {
        $response->set_failed('Found object with a different Kubernetes UID than expected. Not deleting');
      } else {
        my $result = $self->_kube->run('delete', $type, $name);
        if (not $result->success) {
          $response->set_failed($result->output);
        } else {
          $response->set_success;
        }
      }
    } else {
      $response->set_failed("Can't find $type with name $name and uid $uid for deletion");
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
