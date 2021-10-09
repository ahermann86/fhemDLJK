################################################################
#
# $Id$
#
# 2019 by Axel Hermann
#
# FHEM Forum : 
#
################################################################

# Version -   Date   - description
# ah  1.0 - 19.04.20 - first version
# ah  1.1 - 10.09.21 - delete $hash->{helper}->{darr}
#                    - delete unused median
#                    - $attr{global}{modpath} instead of cwd()
#                    - NumStableVals default to 10
#                    - clean up code

package main;

use strict;
use warnings;
use DevIo; # load DevIo.pm if not already loaded
use SetExtensions;
use Math::Trig;

use constant MODULEVERSION => '1.1';

#Prototypes
sub DLJK_Disconnect($);
sub DLJK_Log($); #for development

sub DLJK_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}    = "DLJK_Define";
  $hash->{UndefFn}  = "DLJK_Undef";
  $hash->{ReadFn}   = "DLJK_Read";
  $hash->{ReadyFn}  = "DLJK_Ready";
  $hash->{AttrFn}    = "DLJK_Attr";
  $hash->{AttrList}  = "DebugLog:on,off ".
                       "CisternMaxDist:textField ".
                       "CisternMinDist:textField ".
                       "CisternVolume:textField ".
                       "NumStableVals:textField ".
                       $readingFnAttributes;  
}

# called when a new definition is created (by hand or from configuration read on FHEM startup)
sub DLJK_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);

  my $name = $a[0];

  # $a[1] is always equals the module name "DLJK"

  # first argument is a serial device (e.g. "/dev/ttyUSB0@9600")
  my $dev = $a[2];

  return "no device given" unless($dev);

  # close connection if maybe open (on definition modify)
  DevIo_CloseDev($hash) if(DevIo_IsOpen($hash));

  # add a default baud rate (9600), if not given by user
  $dev .= '@9600' if(not $dev =~ m/\@\d+$/);
  
  # set the device to open
  $hash->{DeviceName} = $dev;

  $hash->{helper}{PARTIAL} = "";

  DevIo_OpenDev($hash, 0, "DLJK_Init");

  $hash->{Module_Version} = MODULEVERSION;

  return undef;
}

# called when definition is undefined
# (config reload, shutdown or delete of definition)
sub DLJK_Undef($$)
{
  my ($hash, $name) = @_;

  DLJK_Disconnect($hash);

  return undef;
}

# called repeatedly if device disappeared
sub DLJK_Ready($)
{
  my ($hash) = @_;

  # try to reopen the connection in case the connection is lost
  return DevIo_OpenDev($hash, 1, "DLJK_Init");
}

# called when data was received
sub DLJK_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $data = DevIo_SimpleRead($hash);
  return if(!defined($data)); # connection lost

  my $buffer = $hash->{helper}{PARTIAL};
  $buffer .= $data;
  my $len = length($buffer);
  
  if ($len >= 4)
  {
    my $sum = 0;
    my $anz = 0;
    my $SumOk = 0;
    my @sbuffer = split(//, $buffer);
    
    if (ord($sbuffer[0]) == 0xFF)  #header present?
    {
      foreach (@sbuffer) 
      {
        $_ = ord($_);
      }
      $anz = @sbuffer;
    }
    
    readingsBeginUpdate($hash);
    
    if ($anz == 4)
    {
      my $AktVal = $sbuffer[1]*256 | $sbuffer[2];
      $sum = ($sbuffer[0] + $sbuffer[1] + $sbuffer[2]) & 0x00FF;
      $SumOk = $sbuffer[3] == $sum;
      if ($SumOk)
      {
        push @{$hash->{helper}->{dValarr}}, $AktVal;
        readingsBulkUpdate($hash, "DistanceRaw", $AktVal);
        #readingsSingleUpdate($hash, "DistanceRaw", $AktVal, 1);
      }
    }
    
    #x Werte sollen stabil sein
    if ($hash->{helper}->{dValarr})
    {
      my $dummy = shift @{$hash->{helper}->{dValarr}} if (@{$hash->{helper}->{dValarr}} >= AttrVal($name, "NumStableVals", 10));
      my $Val = -1;
      my $ValsStable = 1;
      
      foreach (@{$hash->{helper}->{dValarr}})
      {
        if ($Val < 0)
        {
          $Val = $_;
        }
        else
        {
          if ($Val != $_)
          {
            $ValsStable = 0;
          }
        }
      }
      
      my $Val_old = -2; #ReadingsNum("$name", "Distance", -1);
      
      if ($ValsStable)
      {
        if ($Val != $Val_old)
        {
          readingsBulkUpdate($hash, "Distance", $Val);
          #readingsSingleUpdate($hash, "Distance", $Val, 1);
          
          my $x1 = AttrVal($name, "CisternMinDist", 0);
          my $x2 = AttrVal($name, "CisternMaxDist", 0);
          if ($x1 > 0 and $x2 > 0)
          {
            my $y1 = 100;
            my $y2 = 0;
            
            my $y = (( $y2 - $y1)/($x2 - $x1)) * ($Val-$x1) + $y1;
            #readingsSingleUpdate($hash, "Level", (sprintf "%.02f %%", $y), 1);
            readingsBulkUpdate($hash, "Level", (sprintf "%.02f %%", $y));
        
            my $volMax = AttrVal($name, "CisternVolume", 0);
            if ($volMax > 0)
            {
              my $vol = $volMax * $y/100.;
              #readingsSingleUpdate($hash, "Volume", (sprintf "%d", $vol), 1);
              readingsBulkUpdate($hash, "Volume", (sprintf "%d", $vol));
            }
          }
        }
      }
    }
    
    DLJK_Log("DLJK ".__LINE__.": SRead: $sbuffer[0] ".
                              "$sbuffer[1] ".
                              "$sbuffer[2] ".
                              "$sbuffer[3] SumOk: $SumOk" ) if (AttrVal($name, "DebugLog", "off") eq "on");
                              
    readingsEndUpdate($hash, 1);
    $buffer = "";
  }
  
  $buffer = "" if (length($buffer) > 40);  #Damit $buffer nicht unendlich lang wird falls nie ein Header kommt.
  $hash->{helper}{PARTIAL} = $buffer;
}

sub DLJK_Init($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  # Reset
  $hash->{helper}{PARTIAL} = "";
  $hash->{Module_Version} = MODULEVERSION;

  DLJK_Log("DLJK ".__LINE__.": Init" ) if (AttrVal($name, "DebugLog", "off") eq "on");

  return undef;
}

sub DLJK_Attr($$$$)
{
  my ( $cmd, $name, $attrName, $attrValue ) = @_;
  my $hash = $defs{$name};

  return undef;
}

### FHEM HIFN ###
sub DLJK_Disconnect($)
{
  my ($hash) = @_;

  $hash->{ELMState} = "disconnected";

  # close the connection
  DevIo_CloseDev($hash);

  return undef;
}


### HIFN for development ###
sub DLJK_getLoggingTime
{

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
  my $nice_timestamp = sprintf ( "%04d.%02d.%02d_%02d:%02d:%02d",
                                 $year+1900,$mon+1,$mday,$hour,$min,$sec);
  return $nice_timestamp;
}

sub DLJK_Log($)
{
  my ($str) = @_;
  my $strout = $str;
  my $fh = undef;

  open($fh, ">>:encoding(UTF-8)",  "$attr{global}{modpath}/FHEM/70_DLJK_Log.log") || return undef;
  $strout =~ s/\r/<\\r>/g;
  $strout =~ s/\n/<\\n>/g;
  print $fh DLJK_getLoggingTime().": ".$strout."\n";
  close($fh);

  return undef;
}

1;
