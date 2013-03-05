#!/usr/bin/env perl

=head1 NAME

 filter_bogus_genes.pl - Filters out genes with lots of N's from a nuc fasta file or X's from a polypeptide fasta file

=head1 SYNOPSIS

 USAGE: filter_bogus_genes.pl
       --input_file=/path/to/some/fsa_input.fsa
       --output_file=/path/to/some/fsa_output.fsa
       --cutoff=0.7
       --base=nuc
     [ --log=/path/to/file.log
       --debug=3
       --help
     ]

=head1 OPTIONS

B<--input_file,-i>	- a fsa file.  It can be single-FASTA or multi-FASTA files in the list

B<--output_file,-o>	- a fsa file that is essentially the same as the input minus bogus genes.  If all the sequences from the original fasta file are filtered out, then no file is outputted.

B<--cutoff -c> - the ratio of X's or N's in the whole sequence that determines if bogus.  Default is 50%

B<--base -b> - either nuc (nucleotide) or prot (polypeptide)

B<--log,-l>
    Logfile.

B<--debug,-d>
    1,2 or 3. Higher values more verbose.

B<--help,-h>
    Print this message

=head1  CONTACT
    Shaun Adkins
    sadkins@som.umaryland.edu

=cut

use strict;
use warnings;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev pass_through);
use Pod::Usage;

############# GLOBALS AND CONSTANTS ################
my $debug = 1;
my ($ERROR, $WARN, $DEBUG) = (1,2,3);
my $logfh;

my $input_file;
my $output_file;
my $cutoff = 0.5;
my $base;
my $unknown;

my ($header, $seq);

my @fasta_arr;
####################################################

my %options;
my $results = GetOptions (\%options,
                         "input_file|i=s",
                         "output_file|o=s",
                         "cutoff|c=s",
                         "base|b=s",
                         "log|l=s",
                         "debug|d=s",
                         "help|h"
                          );

&check_options(\%options);

$unknown = ($base eq 'nuc') ? 'N' : 'X';

# parse headers and sequences out of the fasta file and push into array
open FILE, $input_file or die "Cannot open fasta file $input_file for reading $!\n";
while (<FILE>) {
    my $line = $_;
    chomp $line;
    if ($line =~ /^>/) {
        my $next_header = substr($line, 1);
        push @fasta_arr, [$header, $seq] unless (! defined($header));
        $header = $next_header;
        $seq = '';
    } else {
        next if ($line =~ /^\s*$/);  #ignore whitespace
        $seq .= uc($line);
    }
}
push @fasta_arr, [$header, $seq];	#push final header-seq combo into our array
close FILE;
    
#test the N and X cutoff for each sequence and remove the "bogus" sequences
for (my $i = $#fasta_arr; $i >= 0; $i--) {
    my $seq_len = length($fasta_arr[$i]->[1]);
    my $bad_chars = ($base eq 'nuc') ? ($fasta_arr[$i]->[1] =~ tr/nN//) : ($fasta_arr[$i]->[1] =~ tr/xX//); 
    if ( ($bad_chars / $seq_len) >= $cutoff) {
    	(my $discard = $input_file) =~ s/\.f(a?st?)?a/\.discard\.fsa/;
    	open DISCARD, ">>$discard" or die "Cannot write to discard file $discard $!\n";
    	print DISCARD $fasta_arr[$i]->[0], "\n";
    	print DISCARD "$1\n" while ( $fasta_arr[$i]->[1] =~ /(\w{1,60})/g );
    	close DISCARD;
    	&_log($DEBUG, "$input_file header $fasta_arr[$i]->[0] did not meet cutoff for good sequence... writing to discard file");
    	splice(@fasta_arr, $i, 1);
    }
}
        
if (scalar(@fasta_arr) == 0) {	# we do not want to write an empty filtered.fsa file
    exit(0);
} else {
    #write the remaining sequences to a temp file, which will replace the original fasta file;
    open OUT, ">$output_file" or die "Cannot write to output fasta file $output_file $!\n";
    foreach my $f (@fasta_arr) {
    	print OUT $f->[0], "\n";
    	print OUT "$1\n" while ( $f->[1] =~ /(\w{1,60})/g );	#60 chars of sequence per line
    }
    close OUT;
}


sub check_options {
   my $opts = shift;
   if( $opts->{'help'} ) {
       &_pod;
   }
   
   $cutoff = $opts->{'cutoff'} if (defined $opts->{'cutoff'} );

   if( $opts->{'log'} ) {
       open( $logfh, "> $opts->{'log'}") or die("Can't open log file ($!)");
   }

   $debug = $opts->{'debug'} if( $opts->{'debug'} );

   foreach my $req ( qw(input_file output_file base) ) {
       &_log($ERROR, "Option $req is required") unless( $opts->{$req} );
   }
   
   $input_file = $opts->{'input_file'};
   $output_file = $opts->{'output_file'};
   
   if (lc($opts->{'base'}) eq "nuc") {
   	$base = 'nuc';
   } elsif (lc($opts->{'base'}) eq "prot") {
   	$base = 'prot';
   } else {
   	&_log($ERROR, "--base option needs to be either 'nuc' or 'prot'");
   }
}

sub _log {
   my ($level, $msg) = @_;
   if( $level <= $debug ) {
      print STDOUT "$msg\n";
   }
   print $logfh "$msg\n" if( defined( $logfh ) );
   exit(1) if( $level == $ERROR );
}

sub _pod {
    pod2usage( {-exitval => 0, -verbose => 2, -output => \*STDERR} );
}
