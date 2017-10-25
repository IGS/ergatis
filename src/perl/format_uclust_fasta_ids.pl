#!/usr/bin/env perl

=head1 NAME

format_uclust_fasta_ids.pl - Renames uclust-generated FASTA sequence identifiers to a friendlier format.

=head1 SYNOPSIS

./format_uclust_fasta_ids.pl
        --fasta_input=/path/to/FASTA/file
        --output_file=/path/to/desired/output/FASTA/file
        --log=/path/to/log/file
        --debug=/debug/level
        --help
        
=head1 PARAMETERS

B<--fasta_input, -i>
    Input FASTA file generated by the UCLUST executable's --uc2fasta option

B<--output_file, -o>
    Path to where formatted output FASTA file should be written.
    
B<--log, -l>
    Optional. Log file

B<--debug, -d>
    Optional. Debug level (1-4)
    
B<--help>
    Prints out help documentation.

=head1 INPUT

A FASTA file generated by the UCLUTS executable in conjunction with the --uc2fasta option. 
Output from UCLUST contains characters denoting what cluster a specific sequence was placed in
among other things:

    >10773|*|FV55M7V02DXODN rank=0227767 x=1496.0 y=2585.0 length=116
    AAAAGTCTACCGATTTACCTGGGAGGCGGAGCTTGCAGTGAGCCGAGATGGCGCCACTGCACTCCAGCCTGGGCGACAG...

    >10774|*|FV55M7V02EPR9M rank=0077407 x=1816.0 y=3272.5 length=115
    CGGGTGGTGGTTCGTGTCGGCCTATTAGTACCGGTCGGCTGAGCCCGTTGCCGGGCTTGCACCTCCGGCCTATCGACCC...

    >10775|*|FV55M7V02DZ9IH rank=0268274 x=1526.0 y=407.0 length=115
    TTTCGCTGGGGATTTGCTAACCATGTACCAAAAGTATGCAGAAGCCCAAGGATGGCGTTTTGAAGTTATGGAAGCTTCT...

These other characters can cause problems in other applications that index or utilize the sequence identifier. 
Following formatting the sequence identifiers should look like so:

    >FV55M7V02DXODN rank=0227767 x=1496.0 y=2585.0 length=116
    AAAAGTCTACCGATTTACCTGGGAGGCGGAGCTTGCAGTGAGCCGAGATGGCGCCACTGCACTCCAGCCTGGGCGACAG...

    >FV55M7V02EPR9M rank=0077407 x=1816.0 y=3272.5 length=115
    CGGGTGGTGGTTCGTGTCGGCCTATTAGTACCGGTCGGCTGAGCCCGTTGCCGGGCTTGCACCTCCGGCCTATCGACCC...

    >FV55M7V02DZ9IH rank=0268274 x=1526.0 y=407.0 length=115
    TTTCGCTGGGGATTTGCTAACCATGTACCAAAAGTATGCAGAAGCCCAAGGATGGCGTTTTGAAGTTATGGAAGCTTCT...

=head OUTPUT

A FASTA file with formatted sequence identifiers. The number of sequences and sequence data should stay untouched.     

=head1 CONTACT                   

    Cesar Arze
    carze@som.umaryland.edu
    
=cut

use strict;
use Pod::Usage;
use Ergatis::Logger;
use Getopt::Long qw(:config no_ignore_case auto_abbrev pass_through);    
my $logger;

my %options = &parse_options();

open (FASTA, $options{'fasta_input'}) or $logger->logdie("Could not open input FASTA file $options{'fasta_input'}: $!");
open (OUTFASTA, "> $options{'output_file'}") or $logger->logdie("Could not write to file $options{'output_file'}: $!");

while(my $line = <FASTA>) {
    if ($line =~ /^>/) {
        ## Split the header line one "|" and the last token should be the identifier
        ## we want
        my @tokens = split(/\|/, $line);
        print OUTFASTA ">" . $tokens[2];
    } else {
        ## If it isn't a header line print it as is
        print OUTFASTA $line;
    }
}

close (FASTA);
close (OUTFASTA);

###############################################################################
#####                          SUBROUTINES                                #####
###############################################################################

#----------------------------------------------
# parse command line arguments
#----------------------------------------------
sub parse_options {
    my %opts = ();
    GetOptions(\%opts, 
                'fasta_input|i=s',
                'output_file|o=s',
                'log|l=s',
                'debug|d=s',
                'help') || pod2usage();
                
	&pod2usage( {-exitval => 1, -verbose => 1, -output => \*STDOUT}) if ($opts{'help'} );
	
	## Intialize logger
    my $logfile = $opts{'log'} || Ergatis::Logger::get_default_logfilename();
    my $debug = $opts{'debug'} ||= 4;
    $logger = new Ergatis::Logger( 'LOG_FILE'      => $logfile,
                                   'LOG_LEVEL'     => $debug );
    $logger = Ergatis::Logger::get_logger();
    
    ## Make sure input and output are defined
    defined($opts{'fasta_input'}) || $logger->logdie("Please provide a valid UCLUST-generated FASTA input file.");
    defined($opts{'output_file'}) || $logger->logdie("A valid path to the desired output file is required.");  
    
    return %opts;                          
}