#!/usr/local/bin/perl

=head1  NAME 

hmmpir2bsml.pl - convert hmmpir raw output to BSML

=head1 SYNOPSIS

USAGE: hmmpir2bsml.pl 
        --input=/path/to/somefile.hmmpir.raw 
        --output=/path/to/somefile.hmmpir.bsml
      [ --log=/path/to/some.log
        --debug=4 
        --help
      ]

=head1 OPTIONS

B<--input,-i> 
    Input raw alignment file from an hmmpir search.

B<--output,-o> 
    Output BSML file

B<--debug,-d> 
    Debug level.  Use a large number to turn on verbose debugging. 

B<--log,-l> 
    Log file

B<--help,-h> 
    This help message

=head1   DESCRIPTION

This script is used to convert the raw alignment output from an hmmpir search into BSML.

=head1 INPUT

The input file passed to this script must be a raw alignment file generated by hmmpir.
Define the input file using the --input option.

Illegal characters will be removed from the IDs for the query sequence and subject hit
if necessary to create legal XML id names.  For each element, the original, unmodified 
name will be stored in the "title" attribute of the Sequence element.  You should make 
sure that your ids don't begin with a number.  This script will successfully create a 
BSML document regardless of your ID names, but the resulting document may not pass DTD 
validation.

=head1 OUTPUT

The BSML file to be created is defined using the --output option.  If the file already exists
it will be overwritten.

=head1 CONTACT

    Joshua Orvis
    jorvis@tigr.org

=cut

use strict;
use Log::Log4perl qw(get_logger);
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev);
use BSML::BsmlBuilder;
use BSML::BsmlReader;
use BSML::BsmlParserTwig;
use BSML::BsmlRepository;
use Pod::Usage;
use Workflow::Logger;

my %options = ();
my $results = GetOptions (\%options, 
			  'input|i=s',
              'output|o=s',
              'log|l=s',
              'debug=s',
			  'help|h') || pod2usage();

my $logfile = $options{'log'} || Workflow::Logger::get_default_logfilename();
my $logger = new Workflow::Logger('LOG_FILE'=>$logfile,
				  'LOG_LEVEL'=>$options{'debug'});
$logger = $logger->get_logger();

# display documentation
if( $options{'help'} ){
    pod2usage( {-exitval=>0, -verbose => 2, -output => \*STDOUT} );
}

## make sure all passed options are peachy
&check_parameters(\%options);

## we want a new doc
my $doc = new BSML::BsmlBuilder();

## open the input file for parsing
open (my $ifh, $options{'input'}) || $logger->logdie("can't open input file for reading");

## go through the top of the file and get a few things.
my ($qry_id, $sbj_id, $description, $seq_pair_alignment);
while (<$ifh>) {
    chomp;
    
    if (/Query sequence\: (\S+)\s+matches (\S+)\:\s+(.*)/) {
        ($qry_id, $sbj_id, $description) = ($1, $2, $3);
        
        ## the query sequence only counts up the first whitespace
        if ($qry_id =~ /(.+?)\s+/) {
            $qry_id = $1;
        }

        ## make sure the name is legal
        my $qry_id_orig = $qry_id;
        $qry_id =~ s/[^a-zA-Z0-9\.\-\_]/_/g;

        ## add the query sequence file to the doc
        ##  the use of 'aa' is not guaranteed here, but we're not using it anyway in loading
        my $seq = $doc->createAndAddSequence($qry_id, $qry_id_orig, undef, 'aa', 'protein');
           $seq->addBsmlLink('analysis', "\#hmmpir_analysis");

        ## add the subject sequence file to the doc
        ##  the use of 'aa' is not guaranteed here, but we're not using it anyway in loading
        $seq = $doc->createAndAddSequence($sbj_id, $description, undef, 'aa', 'profile');
        $seq->addBsmlLink('analysis', "\#hmmpir_analysis");

        ## create the seq pair alignment
        $seq_pair_alignment = $doc->createAndAddSequencePairAlignment( refseq => $qry_id,
                                                                       refxref => ":$qry_id",
                                                                       refstart => 0,
                                                                       method => 'hmmpir',
                                                                       compseq => $sbj_id,
                                                                       compxref => ":$sbj_id",
                                                                     );        
        
        last;
    }
}


## we should now be in the region where the domain hits are described.  We'll add Seq-pair-runs
##  to each of our Seq-pair-alignments here
while (<$ifh>) {
    ## these rows should look like this:
    # PF02310     1/1      12   136 ..     1   142 []   -14.7      1.1
    # PF01582     1/1      14   142 ..     1   150 []   189.0  1.4e-53
    my ($model, $domain_num, $domain_of, $qry_start, $qry_stop, $sbj_start, $sbj_stop, $score, $eval);
    if (/(\S+)\s+([0-9]+)\/([0-9]+)\s+(\d+)\s+(\d+).+(\d+)\s+(\d+).+([0-9\.\-e]+)\s+([0-9\.\-e]+)/) {
        ($model, $domain_num, $domain_of, $qry_start, $qry_stop, $sbj_start, $sbj_stop, $score, $eval) = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
        
        ## make sure this model matches the one we know about
        if ($model ne $sbj_id) {
            $logger->logdie("unhandled multiple-model hits find in file");
        }
        
        ## check and make sure we got a seq pair alignment
        if (! defined $seq_pair_alignment) {
            $logger->logdie("attempted to add a seq pair run without a seq pair alignment");
        }
        
        my $run = $doc->createAndAddSequencePairRun(   alignment_pair => $seq_pair_alignment,
                                                       runscore => $score,
                                                       runlength => abs($qry_stop - $qry_start) + 1,
                                                       comprunlength => abs($sbj_stop - $sbj_start) + 1,
                                                       refpos => min($qry_start, $qry_stop) - 1,
                                                       refcomplement => 0,
                                                       comppos => min($sbj_start, $sbj_stop) - 1,
                                                       compcomplement => 0
                                                   );
                                                   
        ## add other attributes of the run
        $doc->createAndAddBsmlAttributes($run, 
                                            e_value    => $eval,
                                            domain_num => $domain_num,
                                            domain_of  => $domain_of
                                        );
    }
}



## add the analysis element
$doc->createAndAddAnalysis(
                            id => "hmmpir_analysis",
                            sourcename => $options{'output'},
                          );

## now write the doc
$doc->write($options{'output'});

exit;


sub check_parameters {
    
    ## make sure input file exists
    if (! -e $options{'input'}) { $logger->logdie("input file $options{'input'} does not exist") }

    ## make user an output file was passed
    if (! $options{'output'}) { $logger->logdie("output option required!") }

    return 1;
}

sub min {
    my ($num1, $num2) = @_;
    
    if ($num1 < $num2) {
        return $num1;
    } else {
        return $num2;
    }
}
