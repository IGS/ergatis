#!/usr/local/bin/perl
use lib (@INC,$ENV{"PERL_MOD_DIR"});
no lib "$ENV{PERL_MOD_DIR}/i686-linux";
no lib ".";

=head1 NAME

train_for_glimmer.pl - you should put a one-line description of your script 
    here

=head1 SYNOPSIS

USAGE: train_for_glimmer.pl 
            --training_seqs=/path/to/somefile.fsa
            --long_orfs_opts='-n -t 1.15'
            --icm_file=/path/to/glimmmer/training.icm
            --input_file=/path/to/input.fsa
            --output_file=/path/to/out.icm
          [ --log=/path/to/log.file
            --help
          ]

=head1 OPTIONS

B<--debug> 
    Debug level.  Use a large number to turn on verbose debugging. 

B<--log,-l> 
    Log file

B<--help,-h>
    This help message

=head1  DESCRIPTION

put a longer overview of your script here.

=head1  INPUT

the input expectations of your script should be here.  pasting in examples of file format
expected is encouraged.

=head1  OUTPUT

the output format of your script should be here.  if your script manipulates a database,
you should document which tables and columns are affected.

=head1  CONTACT

    Kevin Galens
    (kgalens@tigr.org)

=cut

use strict;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev pass_through);
use Pod::Usage;
use Ergatis::Logger;

########GLOBALS#############
use constant BUILD_ICM => '/usr/local/devel/ANNOTATION/glimmer/glimmer3.01/bin/build-icm';
my $longOrfsBin = "/usr/local/devel/ANNOTATION/glimmer/current/bin/long-orfs";
my $training_seqs;
my $icm_file;
my $input_list;
my $output;
my $dontCreate = 0;
my $tmp_dir;
my $longOrfsOpts;
############################

my %options = ();
my $results = GetOptions (\%options, 
                          'training_seqs|t=s',
                          'input_list|i=s',
                          'long_orfs_opts|n=s',
                          'output_file|o=s',
                          'tmp_dir|t=s',
                          'log|l=s',
                          'debug=s',
                          'help|h') || pod2usage();

## display documentation
if( $options{'help'} ){
    pod2usage( {-exitval => 0, -verbose => 2, -output => \*STDERR} );
}

my $logfile = $options{'log'} || Ergatis::Logger::get_default_logfilename();
my $logger = new Ergatis::Logger('LOG_FILE'=>$logfile,
				  'LOG_LEVEL'=>$options{'debug'});
$logger = $logger->get_logger();

## make sure everything passed was peachy
&check_parameters(\%options);

unless($training_seqs || $icm_file) {
    
    #make the input file for build-icm
    open(IN, "< $input_list") or &_die("Cannot open input list");
    my @inputFiles = <IN>;
    close(IN);

    $training_seqs = &makeTrainingFile($tmp_dir, \@inputFiles);
    
    print "\n\nAccessing $training_seqs\n";
    &changeIds($training_seqs);

}

unless($dontCreate) {

    &makeIcmFile($output, $training_seqs);

}

exit(0);

############################ SUB ROUTINES #######################################

sub makeTrainingFile {
    my ($tmp_dir, $inputFiles) = @_;
    my $outFile = "$tmp_dir/tmpFile.seqs";

    if(-e $outFile) {
        system("rm $outFile");
    }
    
    foreach my $file(@{$inputFiles}) {
        chomp $file;

        my $base = $1 if($file =~ m|/([^/]+)\.|);
        
        my $longOrfsCmd = "$longOrfsBin $longOrfsOpts $file $tmp_dir/$base.train";
        print "Running longorfs: $longOrfsCmd\n\n";
        system($longOrfsCmd);

        my $tmpOut = "$tmp_dir/$base.seqs";

        my $extractCmd = "/usr/local/devel/ANNOTATION/glimmer/current/bin/extract -t $file $tmp_dir/$base.train >> $outFile";
        print "Running:\n $extractCmd\n";
        system($extractCmd)
    }

    #system("rm -f $tmp_dir/out.train");

    return $outFile;

}

sub changeIds {
    my $file = shift;
    open(IN, "<$file") or $logger->logdie("Can't open $file");
    open(OUT, ">$file.tmp") or $logger->logdie("Can't open $file.tmp ($!)");
    my $count = 0;
    while(my $line = <IN>) {
        chomp $line;
        if($line =~ /^>/) {
            $line =~ s/^>\S+/>$count/;
            $count++;
        }
        print OUT "$line\n";
        
    }
    close(IN);
    close(OUT);
    system("mv $file.tmp $file");
}

sub makeIcmFile {
    my ($output) = @_;
    
    my $buildIcmCmd = BUILD_ICM." -r $output < $training_seqs";
    print "Running\n$buildIcmCmd\n";
    system($buildIcmCmd);

}

sub check_parameters {
    my $options = shift;
    
    if($options{'training_seqs'}) {
        &_die("option training_seqs does not exist") unless(-e $options{'training_seqs'});
        $training_seqs = $options{'training_seqs'};
    } elsif($options{'input_list'}) {
        &_die("option input_list does not exist") unless(-e $options{'input_list'});
        $input_list = $options{'input_list'};
    } else {
        &_die("one of input_list, training_seqs must exist");
    }

    $longOrfsOpts = $options{'long_orfs_opts'} if($options{'long_orfs_opts'});    

    unless($options{'output_file'}) {
        &_die("Options output_file is required");
    }
    $output = $options{'output_file'};

    unless($options{'tmp_dir'}) {
        &_die("Option tmp_dir is required");
    }
    $tmp_dir = $options{'tmp_dir'};
    $tmp_dir =~ s/\/$//;

    system("mkdir $tmp_dir") unless(-d $tmp_dir);

    if(-e $output) {
        $dontCreate == 1;
    }

}

sub _die {
    my $msg = shift;
    $logger->logdie($msg);
}

########EOF
