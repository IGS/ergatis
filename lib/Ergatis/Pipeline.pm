package Ergatis::Pipeline;

=head1 NAME

Ergatis::Pipeline.pm - A class for representing pipelines

=head1 SYNOPSIS

    use Ergatis::Pipeline;

    my $conf = Ergatis::Pipeline->new( id => '1234', path => '/path/to/some/pipeline.xml' );

=head1 DESCRIPTION

=head1 METHODS

=over 3

=item I<PACKAGE>->new( path => I<'/path/to/some.xml'> )

Returns a newly created "Ergatis::Pipeline" object.

=item I<$OBJ>->path( )

Returns the path to a given pipeline.

=item I<$OBJ>->id( )

Returns the ID of a given pipeline.

=back

=head1 AUTHOR

    Joshua Orvis
    jorvis@tigr.org

=cut

use strict;
use Carp;
use Sys::Hostname;

umask(0000);

## class data and methods
{

    my %_attributes = (
                        path  => undef,
                        id    => undef,
                        debug => 0,
                        debug_file => '/tmp/ergatis.run.debug',
                      );

    ## class variables
    ## currently none

    sub new {
        my ($class, %args) = @_;
        
        ## create the object
        my $self = bless { %_attributes }, $class;
        
        ## set any attributes passed, checking to make sure they
        ##  were all valid
        for (keys %args) {
            if (exists $_attributes{$_}) {
                $self->{$_} = $args{$_};
            } else {
                croak("$_ is not a recognized attribute");
            }
        }
        
        return $self;
    }
    
    sub run {
        my ($self, %args) = @_;
        
        ## path must be defined and exist to run
        if (! defined $_[0]->{path} ) {
            croak("failed to run pipeline: no path set yet.");
        } elsif (! -f $_[0]->{path} ) {
            croak("failed to run pipeline: pipeline file $_[0]->{path} doesn't exist");
        }
        
        ## ergatis cfg is required
        if (! defined $args{ergatis_cfg} ) { croak("ergatis_cfg is a required option") };
        my $run_dir = $args{ergatis_cfg}->val('paths', 'workflow_run_dir') || croak "workflow_run_dir not found in ergatis.ini";
        
        ## create a directory from which to run this pipeline
        if ( -d $run_dir ) {
            ## make a subdirectory for this pipelineid
            $run_dir .= '/' . $self->id;
            if (! -d $run_dir) {
                mkdir $run_dir || croak "failed to create workflow_run_dir: $run_dir : $!";
            }
        } else {
            croak "Invalid workflow_run_dir (doesn't exist) in ergatis.ini: $run_dir";
        }
        
        if (! -e $args{ergatis_cfg}->val('paths','workflow_log4j') ) {
            croak "Invalid workflow_log4j in ergatis.ini : " . $args{ergatis_cfg}->val('paths','workflow_log4j');
        }
        
        my $child_pid = fork;
        if ( $child_pid ){
            while( ! ( -e $self->path ) ){
                sleep 3;
            }
        } else {
            ## these have to stay here or the separation doesn't work right
            close STDOUT;
            close STDERR;
            close STDIN;

            #  Fork again.  This helps separate the background process from
            #  the httpd process.  If we're in the original child, $gpid will
            #  hold the process id of the "grandchild", and if we're in the
            #  grandchild it will be zero.
            my $gpid = fork;
            if (! $gpid){
                ## open the debugging file if needed
                open (my $debugfh, ">>$self->{debug_file}") if $self->{debug};
                
                ##debug
                print $debugfh "debug init\n" if $self->{debug};
                
                chdir $run_dir;
                use POSIX qw(setsid);
                setsid() or die "Can't start a new session: $!";

                ##debug
                print $debugfh "got past the POSIX section\n" if $self->{debug};

                $self->_setup_environment( ergatis_cfg => $args{ergatis_cfg} );

                ##debug
                print $debugfh "got past ENV setup section\n" if $self->{debug};
                
                my $marshal_interval_opt = '';
                if ( $args{ergatis_cfg}->val('workflow_settings', 'marshal_interval') ) {
                   $marshal_interval_opt = "-m " . $args{ergatis_cfg}->val('workflow_settings', 'marshal_interval');
                }
                
                my $runstring = "$ENV{'WF_ROOT'}/RunWorkflow -i $self->{path} -l $self->{path}.log $marshal_interval_opt --init-heap=100m --max-heap=1024m --logconf=" . 
                                $args{ergatis_cfg}->val('paths','workflow_log4j') . " >& $self->{path}.run.out";

                print $debugfh "preparing to run $runstring\n" if $self->{debug};

                my $rc = 0xffff & system($runstring);

                printf $debugfh "system(%s) returned %#04x: $rc" if $self->{debug};
                if($rc == 0) {
                    print $debugfh "ran with normal exit\n" if $self->{debug};
                } elsif ( $rc == 0xff00 ) {
                    print $debugfh "command failed: $!\n" if $self->{debug};
                } elsif (($rc & 0xff) == 0) {
                    $rc >>= 8;
                    print $debugfh "ran with non-zero exit status $rc\n" if $self->{debug};
                } else {
                    print $debugfh "ran with " if $self->{debug};
                    if($rc & 0x80){
                        $rc &= ~0x80;
                        print $debugfh "coredump from " if $self->{debug};
                    }
                    print $debugfh "signal $rc\n" if $self->{debug};
                }

                close $debugfh if $self->{debug};
            }

            exit;
        }
    }
    
    ## accessors
    sub id { return $_[0]->{id} }
    sub path { return $_[0]->{path} }
    
    ## modifiers
    sub set_id { $_[0]->{id} = $_[1] }
    sub set_path { $_[0]->{path} = $_[1] }
    
    sub _setup_environment {
        my ($self, %args) = @_;

        ## remove the apache SERVER variables from the environment
        for my $k (keys %ENV) {
            if ($k =~ /^SERVER_/ ) {
                delete $ENV{$k};
            }
        }

        $ENV{SGE_ROOT} = $args{ergatis_cfg}->val('grid', 'sge_root');
        $ENV{SGE_CELL} = $args{ergatis_cfg}->val('grid', 'sge_cell');
        $ENV{SGE_QMASTER_PORT} = $args{ergatis_cfg}->val('grid', 'sge_qmaster_port');
        $ENV{SGE_EXECD_PORT} = $args{ergatis_cfg}->val('grid', 'sge_execd_port');
        $ENV{SGE_ARCH} = $args{ergatis_cfg}->val('grid', 'sge_arch');

        ## these WF_ definitions are usually kept in the $workflow_root/exec.tcsh file,
        #   which we're not executing.
        $ENV{WF_ROOT} = $args{ergatis_cfg}->val('paths', 'workflow_root');
        $ENV{WF_ROOT_INSTALL} = $ENV{WF_ROOT};
        $ENV{WF_TEMPLATE} = "$ENV{WF_ROOT}/templates";

        $ENV{SYBASE} = '/usr/local/packages/sybase';
        $ENV{PATH} = "$ENV{WF_ROOT}:$ENV{WF_ROOT}/bin:$ENV{WF_ROOT}/add-ons/bin:$ENV{PATH}";
        $ENV{LD_LIBRARY_PATH} = '';
        
        ## some application-specific env vars
        ############
        
        ## for the htab.pl script within the hmmpfam component
        $ENV{HMM_SCRIPTS} = '/usr/local/devel/ANNOTATION/hmm/bin';
        
        ## for the genewise component
        $ENV{WISECONFIGDIR} = '/usr/local/devel/ANNOTATION/EGC_utilities/WISE2/wise2.2.0/wisecfg';
    }
    
}

1==1;

