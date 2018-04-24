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
