#!/usr/bin/env perl
use strict;
use warnings;


my $GPUREG = "perl ./gpureg.pl";


sub g {
    my ($cmd) = @_;
    print ">> $GPUREG $cmd\n";
    system("$GPUREG $cmd") == 0
        or die "Failed: $cmd\n";
}


sub ENC {
    my ($op,$rd,$rs1,$rs2,$imm) = @_;
    return (($op & 0x1f) << 27) |
           (($rd & 0xf)  << 23) |
           (($rs1 & 0xf) << 19) |
           (($rs2 & 0xf) << 15) |
           ($imm & 0x7fff);
}

# opcode
my $OP_ADD_I16  = 0x01;
my $OP_ADDI64   = 0x05;
my $OP_SETP_GE  = 0x06;
my $OP_LD64     = 0x10;
my $OP_ST64     = 0x11;
my $OP_MOV      = 0x12;
my $OP_BPR      = 0x13;
my $OP_BR       = 0x14;
my $OP_RET      = 0x15;
my $OP_LD_PARAM = 0x16;
my $NOP = 0x00000000;

print "\n=== INIT DMEM ===\n";

g("dmem_write 0 0003_0002 0001_0000");
g("dmem_write 1 0007_0006 0005_0004");
g("dmem_write 2 000b_000a 0009_0008");

g("dmem_write 10 0003_0002 0001_0000");
g("dmem_write 11 0007_0006 0005_0004");
g("dmem_write 12 000b_000a 0009_0008");

g("dmem_write 20 0000_0000 0000_0000");
g("dmem_write 21 0000_0000 0000_0000");
g("dmem_write 22 0000_0000 0000_0000");
g("dmem_write 23 0000_0000 0000_0000");

print "\n=== INIT PARAM ===\n";

g("param_write 1 0 0");
g("param_write 2 0 10");
g("param_write 3 0 20");
g("param_write 4 0 11");

print "\n=== PROGRAM IMEM ===\n";

my @prog = (
    ENC($OP_LD_PARAM ,1,0,0,1),
    ENC($OP_LD_PARAM ,2,0,0,2),
    ENC($OP_LD_PARAM ,3,0,0,3),
    ENC($OP_LD_PARAM ,4,0,0,4),
    ENC($OP_MOV      ,5,0,0,0),
    $NOP,
    $NOP,
    ENC($OP_SETP_GE  ,0,5,4,0),
    ENC($OP_BPR      ,0,0,0,18),
    ENC($OP_LD64     ,10,1,0,0),
    ENC($OP_LD64     ,11,2,0,0),
    ENC($OP_ADDI64   ,1,1,0,1),
    ENC($OP_ADDI64   ,2,2,0,1),
    ENC($OP_ADD_I16  ,12,10,11,0),
    ENC($OP_BR       ,0,0,0,7),
    ENC($OP_ADDI64   ,3,3,0,1),
    ENC($OP_ST64     ,12,3,0,0),
    ENC($OP_ADDI64   ,5,5,0,4),
    ENC($OP_RET      ,0,0,0,0),
);

for (my $i=0; $i<@prog; $i++) {
    my $hex = sprintf("%08x",$prog[$i]);
    g("imem_write $i $hex");
}

# print "\n=== RESET PC ===\n";
# g("pcreset");

# print "\n=== RUN ===\n";
# g("run 1");

# print "\n=== WAIT DONE ===\n";

# my $timeout = 200;
# while ($timeout--) {
#     my $out = `$GPUREG done_check`;
#     if ($out =~ /1/) {
#         print "DONE detected\n";
#         last;
#     }
#     sleep 1;
# }

# g("run 0");

# print "\n=== READ RESULT ===\n";
# g("dmem_read 20");
# g("dmem_read 21");
# g("dmem_read 22");

print "\n=== COMPLETE ===\n";