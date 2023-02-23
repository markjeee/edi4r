#!/usr/bin/env ruby
# -*- encoding: iso-8859-1 -*-
#
# Mapping demo: Outbound, from inhouse to EANCOM
#
# Inhouse format: GS1 Germany's WebEDI ASCII interface for ORDERS
# Output  format: EANCOM'02 ORDERS, according to GS1 Germany'
#                 recommendations for application
#                 (EDI-Anwendungsempfehlungen V 2.0 (ORDERS) in EANCOM 2002 S3)
#                 and the general EANCOM 2002 (ORDERS) documentation
# Comments:
#
# Inhouse and output format were selected, because they represent typical
# data structures and tasks for users, and because documentation of
# these formats is freely available.
#
# $Id: webedi2eancom.rb,v 1.1 2006/05/28 16:08:48 werntges Exp $
#
# Author:  Heinz W. Werntges (edi@informatik.fh-wiesbaden.de)
#
# License: This code is put under the Ruby license
#
# Copyright (c) 2006 Heinz W. Werntges, FH Wiesbaden
#

# Include statement during test setup:

$:.unshift File.join(File.dirname(__FILE__), '..', 'lib')
require 'edi4r'
require 'edi4r/edifact'

# Regular include statements:

#require "rubygems"
#require_gem "edi4r"
#require "edi4r/edifact"



class WebEDI_to_EANCOM02_Map_ORDERS
include EDI
  
#  Mengeneinheit_cvt = {'STK' => 'PCE', 'KG' => 'KGM'}
#  UNBsender_cvt = {'10' => '4333099000009', # Kaufhof ILN
#			    '1034' => '(C+C ILN)',
#			    '1037' => '(extra ILN)',
#			    '1063' => '(real,- ILN)',
#			    # etc.
#			    }

  attr_accessor :with_rff_va
#
# Variable names for header record, derived from original documentation
# Adaptations:
#   lower-case names, no umlaut chars, uniqueness of name (see "ust-id")
#

  def processHeader( line )
    bestellung, satzartkennung, iln_lieferanschrift, iln_kaeufer, 
    bestellnummer, releasenummer, 
    iln_lieferant, lieferantennummer, ust_id_lieferant,
    abteilung_beim_kaeufer, ust_id_kaeufer, 
    iln_rechnungsempfaenger, abteilung_beim_rechnungsempfaenger, ust_id_re,
    abteilung_der_lieferanschrift,
    iln_endempfaenger, abteilung_beim_endempfaenger,
    datum_der_bestellung, lieferdatum_gefordert, pick_up_datum,
    waehrung, nr_der_werbeaktion, von_um, bis, _others = line.split(';')
    
    raise "Header line mismatch: Too many fields" unless _others.nil?

    # Store for consistency checks at line item level:
    @unique_document_id=[iln_lieferanschrift, iln_kaeufer, bestellnummer]

    unb = @ic.header
    unb.cS002.d0004 = iln_kaeufer
    unb.cS002.d0007 = 14
    unb.cS003.d0010 = iln_lieferant
    unb.cS003.d0007 = 14
#    unb.d0035 = '1' if whatever ...
   
    bgm = @msg.new_segment("BGM")
    bgm.cC002.d1001 = bestellung # expected: '220'
    bgm.cC106.d1004 = bestellnummer
    bgm.d1225 = 9
    @msg.add(bgm)
   
    raise "Mandatory element missing: datum_der_bestellung" if datum_der_bestellung.empty?
    dtm = @msg.new_segment("DTM")
    dtm.cC507.d2005 = 137
    dtm.cC507.d2380 = datum_der_bestellung
    dtm.cC507.d2379 = 102
    @msg.add(dtm)

    unless lieferdatum_gefordert.empty?
      dtm = @msg.new_segment("DTM")
      dtm.cC507.d2005 = 2
      lieferdatum_gefordert =~ /(\d\d\d\d)(\d\d)(\d\d)/
      date = $1+$2+$3 # showing off a bit here...
      if von_um.empty? and bis.empty?
        dtm.cC507.d2380 = date
        dtm.cC507.d2379 = 102
      elsif bis.empty?
        raise "Format error in 'von_um'" unless von_um =~ /\d*(\d\d\d\d)$/
        dtm.cC507.d2380 = date+$1
        dtm.cC507.d2379 = 203
      else
        raise "Format error in 'von_um'" unless von_um =~ /\d*(\d\d\d\d)$/
        von = $1
        raise "Format error in 'bis'" unless bis =~ /\d*(\d\d\d\d)$/
	bis = $1
        dtm.cC507.d2380 = date+von+date+bis
        dtm.cC507.d2379 = 719
      end
      @msg.add(dtm)
    end

    unless pick_up_datum.empty?
      dtm = @msg.new_segment("DTM")
      dtm.cC507.d2005 = '200'
      dtm.cC507.d2380 = pick_up_datum
      dtm.cC507.d2379 = '102'
      @msg.add(dtm)
    end

    unless nr_der_werbeaktion.empty?
      rff = @msg.new_segment("RFF")
      cde = rff.cC506
      cde.d1153 = 'PD'
      cde.d1154 = nr_der_werbeaktion
      @msg.add(rff)
    end
      
    # Use a loop for the NAD group

    [ [iln_lieferant, 'SU', nil, nil, lieferantennummer, ust_id_lieferant],
      [iln_kaeufer,   'BY', abteilung_beim_kaeufer, 'PD', nil, ust_id_kaeufer],
      [iln_rechnungsempfaenger, 'IV', abteilung_beim_rechnungsempfaenger, 'OC', nil, ust_id_re],
      [iln_lieferanschrift, 'DP', abteilung_der_lieferanschrift, 'DL', nil, nil],
      [iln_endempfaenger,   'UC', abteilung_beim_endempfaenger, 'GR', nil, nil]
      ].each do |nad_params|
      iln, qu, dept, qu_dept, no, ust_id = nad_params

      raise "Mandatory ILN missing for #{qu}" if iln.nil? or iln.empty?
      nad = @msg.new_segment("NAD")
      nad.d3035 = qu
      cde = nad.cC082
      cde.d3039 = iln
      cde.d3055 = '9'
      @msg.add(nad)
      
      # Special treatment - depending segments - in some cases:
      
      if qu=='SU' and no and !no.empty?
        rff = @msg.new_segment("RFF")
        cde = rff.cC506
        cde.d1153 = 'YC1'
	cde.d1154 = no
	@msg.add(rff)
      end

      if with_rff_va
        # ust_id: reserved for INVOIC ?!
        unless ust_id.nil?
          rff = @msg.new_segment("RFF")
          cde = rff.cC506
          cde.d1153 = 'VA'
          cde.d1154 = ust_id
          @msg.add(rff)
        end
      end

      if dept and !dept.empty?
        cta = @msg.new_segment("CTA")
        cta.d3139 = qu_dept
        cta.cC056.d3413 = dept
        @msg.add(cta)
      end

    end

    unless waehrung.empty?
      seg = @msg.new_segment("CUX")
      cde = seg.aC504.first # [0]
      cde.d6347 = '2'
      cde.d6345 = waehrung
      cde.d6343 = '9'
      @msg.add(seg)
    end
      
  end


  def processItem( line )
  
    bestellung, satzartkennung, iln_lieferanschrift, iln_kaeufer,
    bestellnummer, 
    positionsnummer, ean, artikelbezeichnung, farbe, groesse,
    lieferantenartikelnummer, kaeuferartikelnummer,
    bestellmenge, einheit, preisbezugseinheit, ek, vk = line.split(';')

    # Consistency check
    if @unique_document_id != [iln_lieferanschrift, iln_kaeufer, bestellnummer]
      puts @unique_document_id
      puts [iln_lieferanschrift, iln_kaeufer, bestellnummer]
      raise "Item does not match header!"
    end

    # LIN
    lin = @msg.new_segment("LIN")
    lin.d1082 = positionsnummer
    lin.cC212.d7140 = ean
    lin.cC212.d7143 = "SRV" unless ean.empty?
    @msg.add(lin)

    #PIA
    if ean.empty?
      raise "Mandatory article id missing" if lieferantenartikelnummer.empty?
      pia = @msg.new_segment("PIA")
      pia.d4347 = '5'
      cde = pia.cC212[0]
      cde.d7140 = lieferantenartikelnummer
      cde.d7143 = 'SA'
      cde.d3055 = '91'
    end

    unless kaeuferartikelnummer.empty? and lieferantenartikelnummer.empty?
      pia = @msg.new_segment("PIA")
      pia.d4347 = '1'
      cde = pia.aC212[0]
      if !lieferantenartikelnummer.empty?
        cde.d7140 = lieferantenartikelnummer
        cde.d7143 = 'SA'
	cde.d3055 = '91'
	if !kaeuferartikelnummer.empty?
	  cde = pia.aC212[1]
	  cde.d7140 = kaeuferartikelnummer
	  cde.d7143 = 'IN'
	  cde.d3055 = '92'
	end
      else
	cde.d7140 = lieferantenartikelnummer
	cde.d7143 = 'BP'
	cde.d3055 = '92'
      end
      @msg.add(pia)
    end

    # IMD
    unless artikelbezeichnung.empty?
      imd = @msg.new_segment("IMD")
      imd.d7077 = 'A'
      imd.cC273.a7008[0].value = artikelbezeichnung
      @msg.add(imd)
    end
    
    unless farbe.empty?
      imd = @msg.new_segment("IMD")
      imd.d7077 = 'F'
      imd.cC272.d7081 = '35'
      imd.cC273.a7008[0].value = farbe
      @msg.add(imd)
    end
    
    unless groesse.empty?
      imd = @msg.new_segment("IMD")
      imd.d7077 = 'F'
      imd.cC272.d7081 = '98'
      imd.cC273.a7008[0].value = groesse
      @msg.add(imd)
    end
    
    # QTY
    qty = @msg.new_segment("QTY")
    cde = qty.cC186
    cde.d6063 = '21'
    cde.d6060 = bestellmenge.to_i
    cde.d6411 = einheit unless einheit == 'PCE' # Mengeneinheit_cvt[masseinh_menge]
    cde.root = @ic
    @msg.add(qty)

    # PRI
    [[ek,'AAA'], [vk, 'AAE']].each do |params|
      preis, qu = params
      unless preis.empty?
        pri = @msg.new_segment("PRI")
        cde = pri.cC509
        cde.d5125 = qu
        cde.d5118 = preis.sub(/,/,'.').to_f # decimal sign adjustment
        if qu == 'AAA'
          cde.d5387 = 'LIU'
        else
          cde.d5387 = 'SRP'
          cde.d5284 = preisbezugseinheit
#          cde.d6411 = 'PCE' ??
        end
        @msg.add(pri)
      end
    end

  end


  def wrapup_msg	# Fine as long as we don't create a summary section
    return if @msg.nil?
    uns = @msg.new_segment("UNS")
    uns.d0081 = 'S'
    @msg.add(uns)
    @ic.add(@msg)
    @msg = nil
  end

  # Dispatcher
  #
  # Call specialized mapping methods, depending on record type
  #
  def processLine( line )
    case line
    when /^#.*/		# Skip comment lines

    when /^220;100;.*/	# Header: Triggers a new message
      wrapup_msg
      params = {
                :msg_type => 'ORDERS', 
                :version => 'D', 
                :release => '01B', 
                :resp_agency => 'UN',
                :assigned_code => 'EAN010'
      }
      @msg = @ic.new_message( params )
      processHeader( line.chomp )
	
    when /^220;200;.*/	# Item: Requires a message to add to
      raise "Illegal state: Item before header?" if @msg == nil
      processItem(line.chomp)
	
    when /^\W*$/	# EOF: Add message to interchange
      wrapup_msg
	
    else
      print "Illegal line: #{line}\n"
      wrapup_msg
    end
  end


  def initialize(interchange)
    @msg = nil
    @with_rf_va = false
    @ic = interchange
  end

  def validate
    @ic.validate
  end
  
  def write(hnd)
    @ic.write(hnd)
  end
end # class WebEDI_to_EANCOM02_Mapper


#
# MAIN
#

# We assume that all input is subject to the same mapping code,
# and that all resulting messages go into the same interchange.
# 
# Sender and recipient code of this interchange's UNB segment
# are determined by buyer and supplier of one of the messages.
#
# In "real live", you may have to sort input documents according
# to message type, sender/recipient, and required mapping code.

ic = EDI::E::Interchange.new({:show_una => true,
                               :charset => 'UNOC', 
                               :version => 3,
                               :interchange_control_reference => Time.now.to_f.to_s[0...14] ,
#                               :application_reference => 'EANCOM' ,
                               # :output_mode => :verbatim,
#                               :acknowledgment_request => true,
                               :interchange_agreement_id => 'EANCOM'+'' , # your ref here!
                               :test_indicator => 1,
                             })

with_rff_va = false

while ARGV[0] =~ /^-(\w)/
  opt = ARGV.shift
  case $1
  when 'v' # verbose mode - here: use formatted output
    ic.output_mode = :indented
  when 'a'
    with_rff_va = true
  else
    raise "Option not supported: #{opt}"
  end
end

map = WebEDI_to_EANCOM02_Map_ORDERS.new( ic )
map.with_rff_va = with_rff_va

while (line=gets)
  map.processLine( line )
end
map.wrapup_msg
ic.validate
$stdout.write ic
# ic.inspect
