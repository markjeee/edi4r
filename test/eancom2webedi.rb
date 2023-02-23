#!/usr/bin/env ruby
# -*- encoding: iso-8859-1 -*-
#
# Mapping demo: Inbound, from EANCOM to inhouse
#
# Inhouse format: GS1 Germany's WebEDI ASCII interface for ORDERS
# Output  format: EANCOM'02 ORDERS, according to GS1 Germany'
#                 recommendations for application
#                 (EDI-Anwendungsempfehlungen V 2.0 (ORDERS) in EANCOM 2002 S3)
#                 and the general EANCOM 2002 (ORDERS) documentation including
#                 change requests.
# Comments:
#
# Inhouse and output format were selected, because they represent typical
# data structures and tasks for users, and because documentation of
# these formats is freely available.
#
# $Id: eancom2webedi.rb,v 1.2 2006/07/03 20:20:09 werntges Exp $
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


HeaderRec = Struct.new('HeaderRec',
    :bestellung, :satzartkennung, :iln_lieferanschrift, :iln_kaeufer, 
    :bestellnummer, :releasenummer, 
    :iln_lieferant, :lieferantennummer, :ust_id_lieferant,
    :abteilung_beim_kaeufer, :ust_id_kaeufer, 
    :iln_rechnungsempfaenger, :abteilung_beim_rechnungsempfaenger, :ust_id_re,
    :abteilung_der_lieferanschrift,
    :iln_endempfaenger, :abteilung_beim_endempfaenger,
    :datum_der_bestellung, :lieferdatum_gefordert, :pick_up_datum,
    :waehrung, :nr_der_werbeaktion, :von_um, :bis
)

class Struct::HeaderRec

  def initialize
    self.satzartkennung = '100'
    self.releasenummer = '11'
  end

  def to_s
    [ bestellung, satzartkennung, iln_lieferanschrift, iln_kaeufer, 
      bestellnummer, releasenummer, 
      iln_lieferant, lieferantennummer, ust_id_lieferant,
      abteilung_beim_kaeufer, ust_id_kaeufer, 
      iln_rechnungsempfaenger, abteilung_beim_rechnungsempfaenger, ust_id_re,
      abteilung_der_lieferanschrift,
      iln_endempfaenger, abteilung_beim_endempfaenger,
      datum_der_bestellung, lieferdatum_gefordert, pick_up_datum,
      waehrung, nr_der_werbeaktion, von_um, bis, '' ].join(';')
  end
end


ItemRec = Struct.new('ItemRec',
    :bestellung, :satzartkennung, :iln_lieferanschrift, :iln_kaeufer,
    :bestellnummer, 
    :positionsnummer, :ean, :artikelbezeichnung, :farbe, :groesse,
    :lieferantenartikelnummer, :kaeuferartikelnummer,
    :bestellmenge, :einheit, :preisbezugseinheit, :ek, :vk
)

class Struct::ItemRec

  def initialize( header )
    self.bestellung = header.bestellung
    self.satzartkennung = '200'
    self.iln_lieferanschrift = header.iln_lieferanschrift
    self.iln_kaeufer = header.iln_kaeufer
    self.bestellnummer = header.bestellnummer
  end

  def to_s
    [ bestellung, satzartkennung, iln_lieferanschrift, iln_kaeufer,
      bestellnummer, 
      positionsnummer, ean, artikelbezeichnung, farbe, groesse,
      lieferantenartikelnummer, kaeuferartikelnummer,
      bestellmenge, einheit, preisbezugseinheit, ek, vk, '' ].join(';')
  end
end


class Inhouse_Data

  # Add some constants that cannot be retrieved from EDIFACT

  def initialize
    @headers_since_last_item = 0
    @items_since_last_header = 0
    @records = []
  end

  # Expect/ensure (HeaderRec, ItemRec+)+

  def add( record )
    case record.class.to_s
    when 'Struct::HeaderRec'
      raise "ItemRec missing" if @headers_since_last_item > 0
      @headers_since_last_item += 1
      @items_since_last_header =  0
    when 'Struct::ItemRec'
      raise "HeaderRec missing" if @items_since_last_header == 0 and @headers_since_last_item == 0
      raise "Data inconsistent" if @items_since_last_header >  0 and @headers_since_last_item >  0
      @headers_since_last_item =  0
      @items_since_last_header += 1
    else
      raise "Illegal object: class = #{record.class}"
    end
    @records << record
  end


  def to_s
    raise "ItemRec missing" if @headers_since_last_item > 0
    @records.inject('') {|s, rec| s << rec.to_s << "\r\n"}
  end
end


class Inbound_Mapper
include EDI
  
  def map_header_segments( msg, recs )
    header = HeaderRec.new
    msg.each do |seg|
      seg_name = seg.name
      seg_name += ' ' + seg.sg_name if seg.sg_name
      case seg_name
      when 'UNH'

      when 'BGM'
        header.bestellung = seg.cC002.d1001
        header.bestellnummer = seg.cC106.d1004

        # Demo of add-ons "edifact" and "format" to class Time
      when 'DTM'
        c507 = seg.cC507
        case dtfnc=c507.d2005
        when '137'
          header.datum_der_bestellung = Time.edifact(c507.d2380, c507.d2379)
          header.datum_der_bestellung.format='102'
        when '2'
          if (dtfmt=c507.d2379)=='719'
            seg.cC507.d2380 =~ /(\d{8})(\d{4})(\d{8})(\d{4})/
            raise "Delivery date: Start and end day must be equal" if $1 != $3
            header.lieferdatum_gefordert = $1
            header.von_um = $2
            header.bis = $4 unless $4.empty?
          else
            header.lieferdatum_gefordert = Time.edifact(c507.d2380, c507.d2379)
            header.lieferdatum_gefordert.format='102'
          end
        when '200'
          header.pickup_datum = Time.edifact(c507.d2380, c507.d2379)
          header.pickup_datum.format='102'
        else
          raise "Wrong function in DTM: #{dtfnc}. Expected: 2, 137, 200!"
        end

      when 'RFF SG1'
        cde = seg.cC506
        case cde.d1153
        when 'PD'
          header.nr_der_werbeaktion = cde.d1154
        else
          raise "Unsupported qualifier in RFF: #{cde.d1153}. Expected: PD!"
        end
          
        # Demo: Delegate mapping of a whole SG to some other module
      when 'NAD SG2'
        map_nad_sg2( seg.children_and_self, header ) # skipping segment COM...
      when /\w\w\w SG[235]/
        # ignore - handled by map_nad_sg2() where appropriate

      when 'CUX SG7'
        cde = seg.aC504[0]
        raise "Only '2' expected in DE 6347" if cde.d6347 != '2'
        raise "Only '9' expected in DE 6343" if cde.d6343 != '9'
        header.waehrung = cde.d6345

        # NOTE: We *could* have treated items (LIN SG28) also here, like NAD,
        # but we put them into another method to keep things more modular.

      when 'UNS'
        # ignore

      else
        raise "Unsupported segment/group: #{seg_name}!"
      end
    end
    recs.add header
    header
  end # map_header_segments


  def map_nad_sg2( segs, header )
    function, gln, additional_id, vat_id, p_dept, order_contact, delivery_contact, gr_contact = nil
    segs.each do |seg|
      seg_name = seg.name
      seg_name += ' ' + seg.sg_name unless seg.sg_name.empty?
      case seg_name
      when 'NAD SG2'
        function = seg.d3035 or raise "Mandatory NAD/3035 empty"
        gln = seg.cC082.d3039
        raise "GLN missing or not properly qualified" if gln.nil? or gln.empty? or seg.cC082.d3055 != '9'

      when 'RFF SG3'
        cde = seg.cC506
        if cde.d1153=='YC1'
          additional_id = cde.d1154
        elsif cde.d1153=='VA'
          vat_id = cde.d1154
        else
          raise "RFF SG3: Qualifier in 1153 not supported: #{cde.d1153}"
        end

      when 'CTA SG5'
        case seg.d3139
        when 'PD'
          p_dept = seg.cC056.d3413
        when 'OC'
          order_contact = seg.cC056.d3413
        when 'DL'
          delivery_contact = seg.cC056.d3413
        when 'GR'
          gr_contact = seg.cC056.d3413
        else
          raise "CTA SG5: Qualifier in 3139 not supported: #{seg.d3139}"
        end

      else
        raise "Unsupported segment: #{seg_name}"
      end
    end

    case function
    when 'SU'
      header.iln_lieferant = gln
      header.lieferantennummer = additional_id
      header.ust_id_lieferant = vat_id
    when 'BY'
      header.iln_kaeufer = gln
      header.ust_id_kaeufer = vat_id
      header.abteilung_beim_kaeufer = p_dept
    when 'IV'
      header.iln_rechnungsempfaenger = gln
      header.ust_id_re = vat_id
      header.abteilung_beim_rechnungsempfaenger = order_contact
    when 'DP'
      header.iln_lieferanschrift = gln
      header.abteilung_der_lieferanschrift = delivery_contact
    when 'UC'
      header.iln_endempfaenger = gln
      header.abteilung_beim_endempfaenger = gr_contact
    else
      raise "Unsupported function: #{function}"
    end
  end


  def map_item_segments( segs, recs, header )
    item = ItemRec.new( header )
    segs.each do |seg|
      seg_name = seg.name
      seg_name += ' ' + seg.sg_name if seg.sg_name
      case seg_name
      when 'LIN SG28'
        item.positionsnummer = seg.d1082
        item.ean = seg.cC212.d7140
        raise "Mandatory qual. SRV missing in 7143" unless seg.cC212.d7143=='SRV'

      when 'PIA SG28'
        raise "PIA SG28 / 4347: Only '1' allowed here" unless seg.d4347=='1'
        seg.aC212[0..1].each do |cde|
          case cde.d7143
          when 'IN'
            item.kaeuferartikelnummer = cde.d7140
            raise "PIA SG28/C212/3055: Only '92' allowed here" unless cde.d3055=='92'
          when 'SA'
            item.lieferantenartikelnummer = cde.d7140
            raise "PIA SG28/C212/3055: Only '91' allowed here" unless cde.d3055=='91'
          else
            raise "PIA SG28: Qualifier in 7143 not supported: #{cde.d7143}"
          end
        end

      when 'IMD SG28'
        if seg.d7077=='A'
          item.artikelbezeichnung = seg.cC273.a7008[0]
        elsif seg.d7077=='F'
          if seg.cC272.d7081 == '35'
            item.farbe = seg.cC273.a7008[0]
          elsif seg.cC272.d7081 == '98'
            item.groesse = seg.cC273.a7008[0]
          else
            raise "IMD SG28/C272/7081: Only '35' or '98' allowed here"
          end
        end

      when 'QTY SG28'
        cde = seg.cC186
        raise "QTY SG28/C186/6063: Only '21' allowed here" unless cde.d6063=='21'
        item.bestellmenge = cde.d6060 or raise "Mandatory DE missing: 6060"
        item.einheit = cde.d6411 || 'PCE'

      when 'PRI SG32'
        case (cde = seg.cC509).d5125
        when 'AAA'
          item.ek = cde.d5118
          raise "5387 must bei 'LIU' here!" unless cde.d5387=='LIU'

        when 'AAE'
          item.vk = cde.d5118
          raise "5387 must bei 'SRP' here!" unless cde.d5387=='SRP'
          item.preisbezugseinheit = cde.d5284 || '1'

        else
          raise "PRI SG32: Qualifier in 5125 not supported: #{cde.d5125}"
        end

      else
        raise "Unsupported segment/group: #{seg_name}!"
      end
    end
    recs.add item  
  end

end # class Inbound_Mapper


#
# MAIN
#

# We assume that all input is subject to the same mapping code,
# and that all resulting messages go into the same inhouse file.
# 
# Sender and recipient code of this interchange's UNB segment
# should match buyer and supplier of all messages.
#

if ARGV.empty?
  ic = EDI::E::Interchange.parse($stdin)
else
  File.open(ARGV[0]) {|hnd| ic = EDI::E::Interchange.parse(hnd)}
end
sender_id = ic.header.cS002.d0004
recipient_id = ic.header.cS003.d0010

recs = Inhouse_Data.new
mapper = Inbound_Mapper.new
ic.each do |msg|

  header = mapper.map_header_segments( msg, recs )
  raise "sender id mismatch" if sender_id != header.iln_kaeufer
  raise "recipient id mismatch" if recipient_id != header.iln_lieferant

  msg.find_all {|seg| seg.name=='LIN' && seg.sg_name=='SG28'}.each do |lin|
    mapper.map_item_segments( lin.descendants_and_self, recs, header )
  end

end
$stdout.write recs
