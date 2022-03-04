#!/usr/local/bin/perl

#############################################################################
# Copyright (C) 2006, Matrix Science Limited.                               #
#                                                                           #
# This script is free software. You can redistribute and/or                 #
# modify it under the terms of the GNU General Public License               #
# as published by the Free Software Foundation; either version 2            #
# of the License or, (at your option), any later version.                   #
#                                                                           #
# These modules are distributed in the hope that they will be useful,       #
# but WITHOUT ANY WARRANTY; without even the implied warranty of            #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the              #
# GNU General Public License for more details.                              #
#############################################################################

  use strict;

# print usage information if no arguments supplied  
  unless ($ARGV[0]) {
    print "Usage:\ndecoy.pl [--random] [--append] [--keep_accessions] input.fasta [output.fasta]\n\n";
    print "If --random is specified, the output entries will be random sequences\n";
    print "   with the same average amino acid composition as the input database. \n";
    print "   Otherwise, the output entries will be created by reversing the input\n";
    print "   sequences, (faster, but not suitable for PMF or no-enzyme searches).\n";
    print "If --append is specified, the new entries will be appended to the input\n";
    print "   database. Otherwise, a separate decoy database file will be created.\n";
    print "If --keep_accessions is specified, the original accession strings will\n";
    print "   be retained. This is necessary if you want to use taxonomy and the\n";
    print "   taxonomy is derived from the accessions, (e.g. NCBI gi2taxid).\n";
    print "   Otherwise, the string ###REV### or ###RND### is prepended to the\n";
    print "   original accession strings.\n";
    print "You cannot specify both --append and --keep_accessions.\n";
    print "An output path must be supplied unless --append is specified.\n";
    exit 1;
  }

# get arguments and perform basic error checking
  my($random, $append, $keep_accessions, $inFile, $outFile);
  for (my $i = 0; $i <= $#ARGV; $i++) {
    if (lc($ARGV[$i]) eq "--random") {
      $random = 1;
    } elsif (lc($ARGV[$i]) eq "--append") {
      $append = 1;
    } elsif (lc($ARGV[$i]) eq "--keep_accessions") {
      $keep_accessions = 1;
    } elsif ($ARGV[$i] =~ /^-/) {
      die "Error: unrecognised argument: " . $ARGV[$i];
    } elsif (!$inFile) {
      $inFile = $ARGV[$i];
    } elsif (!$outFile) {
      $outFile = $ARGV[$i];
    } else {
      die "Error: too many arguments";
    }
  }
  
  unless ($inFile && -s $inFile) {
    die "Error: must specify valid input file";
  }
  
  unless ($append) {
    if ($outFile) {
      if (-e $outFile) {
        print "Warning: output file already exists. OK to overwrite? [No] ";
        my $answer = <STDIN>;
        unless ($answer =~ /^y/i) {
          exit 1;
        }
      }
    } else {
      die "Error: must specify output file path";
    }  
  }
  
  if ($append && $keep_accessions) {
    die "Error: cannot combine --append and --keep_accessions";
  }
  
# so far so good, try to open input and output files
  if ($append) { 
    open (INFILE,  "+<$inFile")          || die "Error: cannot open input file";
    open (OUTFILE, "+>$inFile" . ".tmp") || die "Error: cannot create temp file";
  } else {
    open (INFILE,  "<$inFile")           || die "Error: cannot open input file";
    open (OUTFILE, ">$outFile")          || die "Error: cannot open output file";
  }
  
# use the same EOL for the output as found in the input file
  binmode INFILE;
  binmode OUTFILE;
  $/ = "\012>";
  my $eol;
  while (<INFILE>) {
    if (length($_) > 1) {
      if (/\015\012/) {
        $eol = "\015\012"; #DOS
      } else {
        $eol = "\012"; #Unix
      }
      last;
    } else {
      next;
    }
  }

# set the cursor to start of file + 1 character, (i.e. skip first ">")
  seek(INFILE, 1, 0);

# read a complete sequence entry at a time
  $/ = "$eol>";
  
# for --random, need to determine average AA composition of input database
	my(@AACount, @residue, $denominator);
  if ($random) {
    while (<INFILE>) {
      my($title, $seq) = split(/$eol/o, $_, 2);
      $_ = uc($seq);
      $AACount[0] += tr/A//;
      $AACount[1] += tr/B//;
      $AACount[2] += tr/C//;
      $AACount[3] += tr/D//;
      $AACount[4] += tr/E//;
      $AACount[5] += tr/F//;
      $AACount[6] += tr/G//;
      $AACount[7] += tr/H//;
      $AACount[8] += tr/I//;
      $AACount[9] += tr/J//;
      $AACount[10] += tr/K//;
      $AACount[11] += tr/L//;
      $AACount[12] += tr/M//;
      $AACount[13] += tr/N//;
      $AACount[14] += tr/O//;
      $AACount[15] += tr/P//;
      $AACount[16] += tr/Q//;
      $AACount[17] += tr/R//;
      $AACount[18] += tr/S//;
      $AACount[19] += tr/T//;
      $AACount[20] += tr/U//;
      $AACount[21] += tr/V//;
      $AACount[22] += tr/W//;
      $AACount[23] += tr/X//;
      $AACount[24] += tr/Y//;
      $AACount[25] += tr/Z//;
    }
  # $denominator is total number of residues
    foreach (@AACount) {
      $denominator += $_;
    }
  # populate lookup vector with residues in same proportions
    for (my $i = 0; $i < 26; $i++) {
      for (my $j = 0; $j < int($AACount[$i] * 10000 / $denominator + 0.5); $j++) {
        push @residue, chr(65 + $i);
      }
    }
  # ensure vector fully populated by topping up with common residue A
    while (scalar(@residue) < 10000) {
      push @residue, "A";
    }
  }

# set the cursor to start of file + 1 character, (i.e. skip first ">")
  seek(INFILE, 1, 0);

# loop through input file and create the output file
  while (<INFILE>) {
    my($title, $seq) = split(/$eol/o, $_, 2);
    my($accession, $description) = split(/\s+/, $title, 2);
  # remove any non-residue characters from input sequence
    $seq =~ tr/a-zA-Z//cd;
    my @pieces;
    if ($random) {
      if ($keep_accessions) {
        print OUTFILE ">" . $accession . " Random sequence, was " . $description . $eol;
      } else {
        print OUTFILE ">###RND###" . $accession . " Random sequence, was " . $description . $eol;
      }
    # create random sequence
      my $len = length($seq);
      $seq = "";
      for (my $i = 0; $i < $len; $i++) {
        $seq .= $residue[int(rand 10000)];      
      }
    # chop into little pieces for output
      @pieces = $seq =~ /(.{1,60})/g;
      foreach (@pieces) {
        print OUTFILE $_ . $eol;
      }
    } else {
      if ($keep_accessions) {
        print OUTFILE ">" . $accession . " Reverse sequence, was " . $description . $eol;
      } else {
        print OUTFILE ">###REV###" . $accession . " Reverse sequence, was " . $description . $eol;
      }
    # create reversed sequence
      $seq = reverse $seq;
    # chop into little pieces for output
      @pieces = $seq =~ /(.{1,60})/g;
      foreach (@pieces) {
        print OUTFILE $_ . $eol;
      }
    }
  }

# if --append, copy output to end of input file and delete temp file
  if ($append) {
    seek(OUTFILE, 0, 0);
    while (<OUTFILE>) {
        print INFILE $_;      
    }
    close OUTFILE;
    unlink "$inFile" . ".tmp";
  }

  exit 0;
  