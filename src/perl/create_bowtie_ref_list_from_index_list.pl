#!/usr/bin/env perl

use strict;
use warnings;
use Ergatis::Logger;
use File::Basename;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev pass_through);

my $logger;
## Assuming only place you are running this is CloVR so this should be in our path
my $DESCRIBE_DATASET_EXE = "vp-describe-dataset";
my @SUFFIX_LIST = (".rev.1.ebwt", ".rev.2.ebwt", ".1.ebwt", ".2.ebwt", ".3.ebwt", ".4.ebwt", ".ebwt");
my @index_list = ();

my %options = parse_options();
my $index_list = $options{'input_file_list'};
my $refs_out = $options{'output_list'};
my $clovr = $options{'clovr'};

## Now get our basename of files for the creation of our bowtie reference list
my @reference_basenames = parse_index_list($index_list, $clovr);

## Finally, create our new list of files to be used by the bowtie component
open (OUT_REFS, "> $refs_out") or $logger->logdie("Could not open output reference list $refs_out for writing: $!");
foreach my $reference (@reference_basenames) {
    print OUT_REFS $reference . ".idx\n";
}

close OUT_REFS;

#----------------------------------------------------------
# Parse an index list file (generated by bowtie-build) 
# or the stdout of a vp-describe-dataset call (CloVR only)
# to build a list of references that can be used by the
# bowtie component
#----------------------------------------------------------
sub parse_index_list {
    my ($index, $clovr) = @_;
    my $uniq_refs = {};
    my @ret_refs = ();
    my $index_fh;
    my $ref_file;

    ## If we are using CloVR we want to open a file handle on stdout of a 
    ## vp-describe-dataset call otherwise we just want to open the file list
    if ($clovr) {
        open($index_fh, "vp-describe-dataset --tag-name=$index |") or $logger->logdie("Could not run vp-describe-dataset on tag $index");
    } else {
        open ($index_fh, $index) or $logger->logdie("Could not open bowtie-build index file $index: $!");
    }

    while (my $line = <$index_fh>) {
        chomp ($line);
        next if ($line =~ /.idx$/);
        next if ($line =~ /^METADATA/);

        ## If we are dealing with tags (CloVR specific) we want to split on 
        ## tab
        if ($line =~ /^FILE/) {
            (undef, $ref_file) = split(/\t/, $line);
        } else {
            $ref_file = $line;
        }

        my ($basename, $path, $suffix) = fileparse($ref_file, @SUFFIX_LIST);

        ## Make sure we haven't seen this already
        if (exists($uniq_refs->{$basename})) {
            next;
        } else {
            ## A new file! We need to add this to our hash and push it onto 
            ## the array being returned
            $uniq_refs->{$basename} = 1;
            push(@ret_refs, $path . "/" . $basename);
        }
    }

    close $index_fh;
    return @ret_refs;
}

#----------------------------------------------------------
# run unix system command and determine whether or not
# the command executed successfully
#----------------------------------------------------------
sub run_system_cmd {
    my $cmd = shift;
   
    my $res = `$cmd`;
    my $success = $? >> 8;

    unless ($success == 0) {
        $logger->logdie("Command \"$cmd\" failed.");
    }   

    return $res;
}

#----------------------------------------------------------
# parse command-line options
#----------------------------------------------------------
sub parse_options {
    my %opts = ();
    GetOptions(\%opts,
                'input_file_list|i=s',
                'output_list|o=s',
                'clovr',
                'log|l:s',
                'debug|d:s',
                'help') || pod2usage();
                 
    &pod2usage( {-exitval => 1, -verbose => 1, -output => \*STDOUT}) if ($opts{'help'} );        
    
    ## Configure logger
    my $logfile = $opts{'log'} || Ergatis::Logger::get_default_logfilename();
    $logger = new Ergatis::Logger( 'LOG_FILE'   =>  $opts{'log'},
                                   'LOG_LEVEL'  =>  $opts{'debug'} );
    $logger = Ergatis::Logger::get_logger();
    
    ## Make sure our parameter are declared correctly
    defined ($opts{'input_file_list'}) || $logger->logdie('Please specify a valid input file list or CloVR tag name');
    defined ($opts{'output_list'}) || $logger->logdie('Path to a desired output file must be provided');
    
    return %opts;
}
