#!/usr/bin/env ruby
#
# Inter-Standard converter module SEDAS --> EANCOM'02
#
# Inhouse format: GS1 Germany's SEDAS V5 (April 1993)
# Output  format: EANCOM'02 INVOIC, according to GS1 Germany'
#                 recommendations for application
#                 (EDI-Anwendungsempfehlungen V 2.0 (INVOIC) in EANCOM 2002 S3)
#                 and the general EANCOM 2002 (INVOIC) documentation
# Comments:
#
# Inhouse and output format were selected, because they represent typical
# data structures and tasks for users, and because documentation of
# these formats is freely available.
#
# $Id: sedas2eancom02.rb,v 1.3 2007/04/12 21:54:27 werntges Exp $
#
# Author:  Heinz W. Werntges (edi@informatik.fh-wiesbaden.de)
#
# License: This code is put under the Ruby license
#
# Copyright (c) 2007 Heinz W. Werntges, FH Wiesbaden
#

# Include statement during test setup:
#if $DEBUG
#  $:.unshift File.join(File.dirname(__FILE__), '..', 'lib')
#else
require 'rubygems'
#end

require 'edi4r'
require 'edi4r/edifact'
require 'edi4r/sedas'
require 'logger'


#
# Helper methods
#
# bbbbbbb 00000 c
# 1313131 31313 1

def bbn_to_gln( bbn )
  bbn = "%07d" % bbn
  raise "Keine bbn: #{bbn}" unless bbn =~ /\d{7}/
  gln = bbn + '0' * (13-bbn.length)
  sum = i = 0
  gln.split('').reverse_each do |c|
    sum += c.hex * ((i&1==1) ? 3 : 1)
    i += 1
  end
  sum %= 10
  return gln if sum==0
  gln[-1] = ?9+1 - sum
  gln
end

def to_value( komma_kz, field )
  case komma_kz # Nr. 4
  when 0: nil
  when 1: field.to_i
  when 2: field.to_i / 10.0
  when 3: field.to_i / 100.0
  when 4: field.to_i / 1000.0
  when 5: field.to_i / 10000.0
  else    raise ArgumentError, "Unzulaessiges Komma-KZ: #{komma_kz}"
  end
end

def qkey_to_qualifier6411( qkey ) # Nr. 5
  case qkey
  when nil: nil       # not given - don't fill qualifier
  when 0:   nil       # empty - should not occur, consider a raise()
  when 11:  nil       # PCE
  when 12: 'KGM'
  when 13: 'LTR'
  when 14: 'MTR'
  when 15:  nil       # PCE (Anzahl Display/Sortimentseinheiten)
  when 16:  nil       # PCE (Anzahl gesamt in den Display/Sortimentseinheiten)
    # FIXME: 15, 16 nicht spezifiziert - Sonderbehandlung erforderlich?
  else      raise "QTY/PRI: Unbekannter 'Mengenschluessel: '#{qkey}'"
  end
end
    
class EDI::E::Message
  @@curr_year = Time.now.year.to_s # For add_dtm()

  # d2380: Expect Fixnum or String, JMMTT or JJMMTT if d.2379.nil?
  def add_dtm( data )
    return nil if data[:d2380].nil? || data[:d2380] =~ /^\s*$/
    dtm = self.new_segment("DTM")
    dtm.cC507.d2005 = data[:d2005]
    if data[:d2379].nil? # Auto-format
      if data[:digits]==5 # Expected: 5 or 6
        d = @@curr_year[0,3] + "%05d" % data[:d2380].to_i
      else
        d = @@curr_year[0,2] + "%06d" % (data[:d2380].to_i % 1000000)
      end
      dtm.cC507.d2380 = d
      dtm.cC507.d2379 = 102
      raise ArgumentError, "Datumsformat nicht 102!" if dtm.cC507.d2380.size != 8
    else                 # User takes full control
      dtm.cC507.d2380 = data[:d2380]
      dtm.cC507.d2379 = data[:d2379]
    end
    self.add(dtm)
  end

  def add_nad( data )
    return nil if (data[:d3039].nil? || data[:d3039] =~ /^\s*$/) && data[:d3036_1].nil?
    seg = self.new_segment('NAD')
    seg.d3035 = data[:d3035]
    if data[:d3039].nil? || data[:d3039] =~ /^\s*$/
      seg.cC080.a3036[0].value = data[:d3036_1].strip
      seg.d3164 = data[:d3164].strip
      seg.cC059.a3042[0].value = data[:d3042_1].strip
      seg.d3251 = data[:d3251]
    else
      seg.cC082.d3039 = bbn_to_gln(data[:d3039])
      seg.cC082.d3055 = 9
    end
    self.add seg
  end

  def add_rff( data )
    return nil if data[:d1154].nil? || data[:d1154] =~ /^\s*$/
    seg = self.new_segment('RFF')
    seg.cC506.d1153 = data[:d1153]
    if data[:d1154].is_a? Fixnum
      seg.cC506.d1154 = data[:d1154]
    else
      seg.cC506.d1154 = data[:d1154].strip
    end
    self.add seg
  end

  def add_tax( data )
    seg = self.new_segment("TAX")
    return nil unless data[:ust_kz]
    case kz=data[:ust_kz]
    when 0:   return nil # skip!
    when 1,6: seg.cC243.d5278, seg.d5305 =  0, 'E' # 0%
    when 2,7: seg.cC243.d5278, seg.d5305 =  7, 'S' # 7%
    when 3:   seg.cC243.d5278, seg.d5305 = 19, 'S' # 19%
    when 8:   seg.cC243.d5278, seg.d5305 = 16, 'S' # 16%
      $log.warn("add_tax: USt-Kz 8! pos_nr=#{data[:pos_nr]}")
    else      raise "TAX: Unbekanntes Umsatzsteuer-Kennzeichen: '#{kz}' (pos_nr=#{data[:pos_nr]})"
    end
    seg.cC241.d5153= 'VAT'
    seg.d5283 = 7
    self.add seg
  end

  def add_pat( data )
    seg = self.new_segment("PAT")
    seg.d4279 = data[:d4279] 
    seg.cC112.d2475 = data[:d2475]
    seg.cC112.d2009 = data[:d2009]
    seg.cC112.d2151 = data[:d2151]
    seg.cC112.d2152 = data[:d2152]
    self.add seg
  end

  def add_alc( data )
    seg = self.new_segment("ALC")
    seg.d5463 = data[:d5463] || 'A' 
    seg.cC214.d7161 = data[:d7161] || 'DI'
    seg.d1227 = data[:d1227]
    self.add seg
  end

  def add_lin( data )
    seg = self.new_segment("LIN")
    return nil if data[:d7140].nil?
    seg.d1082 = data[:d1082]
    seg.cC212.d7140 = bbn_to_gln( data[:d7140] )
    seg.cC212.d7143 = data[:d7143] || 'SRV'
    if data[:c829_d1082]
      seg.cC829.d5495 = data[:c829_d5495] || 1
      seg.cC829.d1082 = data[:c829_d1082]
    end
    self.add seg
  end

  def add_pia( data )
    seg = self.new_segment("PIA")
    return nil if data[:d4347].nil?
    seg.d4347 = data[:d4347] # e.g., 1
    cde = seg.aC212[0]
    cde.d7140 = 
      data[:d7140].respond_to?(:strip) ? data[:d7140].strip : data[:d7140]
    cde.d7143 = data[:d7143]
    cde.d3055 = data[:d3055]
    self.add seg
  end

  def add_imd( data )
    seg = self.new_segment("IMD")
    return nil if data[:d7077].nil?
    seg.d7077 = data[:d7077]
    seg.cC272.d7081 = data[:d7081]
    seg.cC272.d3055 = data[:d7081_3055]
    seg.cC273.d7009 = data[:d7009]
    seg.cC273.d3055 = data[:d7009_3055]
    seg.cC273.a7008[0].value = 
      data[:d7008_1].respond_to?(:strip) ? data[:d7008_1].strip : data[:d7008_1]
    self.add seg
  end

  def add_qty( data )
    seg = self.new_segment("QTY")
    return nil if data[:qkey]==0
    seg.cC186.d6411 = qkey_to_qualifier6411( data[:qkey] )
    seg.cC186.d6063 = data[:d6063]
    seg.cC186.d6060 = data[:d6060]
    self.add seg
  end
    
  def add_pri( data )
    seg = self.new_segment("PRI")
    case data[:pkey]
    when nil:  return nil         # FIXME: Check! / Don't use this DE
    when 0, 9: return nil         # empty or w/o charge
    when 1:
    when 2:    seg.cC509.d5284 = 100
    when 3:    seg.cC509.d5284 = 1000
    else       raise "PRI: Unbekannter 'Preisschluessel: '#{data[:pkey]}'"
    end
    seg.cC509.d5125 = data[:d5125]
    seg.cC509.d6411 = qkey_to_qualifier6411( data[:qkey] )
    seg.cC509.d5118 = data[:d5118]
    self.add seg
  end

  def add_moa( data )
    seg = self.new_segment("MOA")
    seg.cC516.d5025 = data[:d5025]
    seg.cC516.d5004 = data[:d5004]
    self.add seg
  end

  def add_pcd( data )
    seg = self.new_segment("PCD")
    seg.cC501.d5245 = data[:d5245]
    seg.cC501.d5482 = data[:d5482]
    self.add seg
  end

  def add_rte( data )
    seg = self.new_segment("RTE")
    seg.cC128.d5419 = data[:d5419]
    seg.cC128.d5420 = data[:d5420]
    self.add seg
  end

end


Verkettung01_Felder = Struct.new(:v_nad_by, :v_nad_ds, 
                                 :v_nad_su_va, :v_nad_su_fc, :v_nad_by_va,
                                 :ls_a_kz, :ls_a_nr1, :ls_a_nr2)

Verkettung02_Felder = Struct.new(:empty, :ust_prozentsatz,
                                 :preisschluessel, :komma_kz_p, :grundpreis,
                                 :mengenschluessel, :komma_kz_m, :menge)


class SEDAS_to_EANCOM02_Map_INVOIC
include EDI

  attr_accessor :with_ung


  def map_00_to_unb( s00 )
    unb = @ic.header
    unb.cS002.d0004 = bbn_to_gln( s00.bbn_absender_dt )
    unb.cS002.d0007 = 14
    unb.cS003.d0010 = bbn_to_gln( s00.bbn_empfaenger_dt )
    unb.cS003.d0007 = 14
    unb.cS004.d0017 = s00.datum_erstellung
    unb.cS004.d0019 = '0000'
    unb.d0035 = 1 if s00.dateistatus =~ /[KT]/
    unb.cS005.d0022 = s00.datei_archiv_nr.strip
    unb.d0020 = s00.lfd_nr_dt_empfaenger
    $ung_0048 = {} # Reset store for uniqueness check of UNG ref numbers
  end


  def map_01_to_ung( s01 )
    grp = @ic.new_msggroup( @msg_params )
    ung = grp.header
    ung.cS006.d0040 = bbn_to_gln( s01.bbn_absender )
    ung.cS006.d0007 = 14
    ung.cS007.d0044 = bbn_to_gln( s01.bbn_empfaenger )
    ung.cS007.d0007 = 14
    ung.cS004.d0017 = s01.datum_erstellung
    ung.cS004.d0019 = '0000'
    log_nr = s01.log_nr
    warn "SA01: Log-Nr. #{log_nr} bereits verwendet!" if $ung_0048[log_nr]
    ung.d0048 = log_nr
    $ung_0048[log_nr]=true
    @ic.add grp
    @p = grp
  end


  def map_12_to_325( s_msg, master_data )
    @msg = @p.new_message( @msg_params )
    item_counter = 1

    # Lookahead / out-of-sequence segments first:
    #
    ftx_in_header = []
    # 08 for SA 12/22, 15/25
    s_msg[/[12][25]08/].each do |seg|
      ftx = @msg.new_segment("FTX")
      ftx.d4451 = 'ZZZ'
      ftx.cC108.a4440[0].value = seg.freitext.strip
      ftx.d3453 = 'DE'
      ftx_in_header << ftx
    end
    # 08 for SA 14/24, 17/27
    s_msg[/[12][47]08/].each do |seg|
      ftx = @msg.new_segment("FTX")
      ftx.d4451 = 'SUR'
      ftx.cC108.a4440[0].value = seg.freitext.strip
      ftx.d3453 = 'DE'
      ftx_in_header << ftx
    end

    s01 = Verkettung01_Felder.new
    if seg=s_msg[/[12][25]01/].first # 1201, 2201, 1501, 2501
      s01.v_nad_by = seg.bbn_rechnungsempfaenger
      s01.v_nad_ds = seg.bbn_warenlieferant
      s01.v_nad_su_va = seg.ust_ident_nr_lieferant
      s01.v_nad_su_fc = seg.steuer_nr
      s01.v_nad_by_va = seg.ust_ident_nr_erwerber
      s01.ls_a_kz = seg.ls_auftrag_kz
      s01.ls_a_nr1 = seg.ls_auftrag_nr_1
      s01.ls_a_nr2 = seg.ls_auftrag_nr_2
    else
      s01.ls_a_kz = 0
    end

    # Naming convention:
    #
    # shd = SEDAS header  record, e.g. a SA12/22 or a SA15/25
    # str = SEDAS trailer record, e.g. a SA14/24 or a SA17/27
    #
    shd = s_msg[/[12][25]00/].first # Must exist due to SEDAS msg definition!
    all_str = s_msg[/[12][47]00/]   # Expect one per VAT rate, one at least

    ls_auftrag_array = [[shd.ls_auftrag_kz_1, shd.ls_auftrag_nr_1, 1],
                        [shd.ls_auftrag_kz_2, shd.ls_auftrag_nr_2, 2],
                        [shd.ls_auftrag_kz_3, shd.ls_auftrag_nr_3, 3],
                        [shd.ls_auftrag_kz_4, shd.ls_auftrag_nr_4, 4],
                        [shd.ls_auftrag_kz_5, shd.ls_auftrag_nr_5, 5]]

    summe_131 = 0     # Evtl. erst Skonto addieren, siehe ALC (EAB)

    # BGM
    #
    bgm = @msg.new_segment("BGM")
    bgm.cC002.d1001 = 325
    bgm.cC106.d1004 = shd.beleg_nr
    bgm.d1225 = 9
    @msg.add(bgm)

    # All DTM
    #
    @msg.add_dtm(:d2005=> 137, :digits=> 5, :d2380=>shd.datum_liefernachweis)
    @msg.add_dtm(:d2005=>  35, :d2380=> shd.lieferdatum)
    [
     [shd.ls_auftrag_kz, shd.ls_auftrag_nr, shd.auftrags_nr_besteller, 1],
     [s01.ls_a_kz, s01.ls_a_nr1, s01.ls_a_nr2, 2]
    ].each do |a|
      kz, nr1, nr2, no = a
      next unless kz==2 # Lieferdatum von-bis (0JJMMTT)
      dt = if nr1.is_a? String
             @curr_year[0,2]+nr1[1,6]+@curr_year[0,2]+nr2[1,6]
           else
             @curr_year[0,2]+"%06d" % nr1 + @curr_year[0,2]+"%06d" % nr2
           end
      @msg.add_dtm( :d2005=>35, :d2380=>dt, :d2379=>718 ) # CCYYMMDD-CCYYMMDD
    end

    # All FTX
    #
    ftx_in_header.each {|obj| @msg.add(obj)}

    # SG1: RFF-DTM
    #
    case q=shd.s_rechnung_kz  # Nr. 2, Anmerkung 2
    when 0 # empty - skip
    when 6,8
      @msg.add_rff( :d1153=>'IV', :d1154=> shd.s_rechnung_nr )
      @msg.add_dtm( :d2005=> 171, :d2380=> shd.datum_s_beleg )
    when 7,9
      @msg.add_rff( :d1153=>'IV', :d1154=> shd.s_rechnung_nr )
    else
      raise "Kennzeichen S.-Rechnung: ungueltig: #{q}"
    end

    [
     [shd.ls_auftrag_kz, shd.ls_auftrag_nr, shd.auftrags_nr_besteller, 1],
     [s01.ls_a_kz, s01.ls_a_nr1, s01.ls_a_nr2, 2]
    ].each do |a|
      kz, nr1, nr2, no = a
      case kz # Nr. 3, Anmerkung 1
      when nil # treat as empty, should not occur
        $log.warn("ls_auftrag_kz (#{no}) fehlt!")
      when 0  # empty - skip
      when 1
        @msg.add_rff( :d1153=>'DQ', :d1154=> nr1 )
        @msg.add_rff( :d1153=>'ON', :d1154=> nr2 )
      when 2  # skip - treated earlier (DTM)
      when 3
        @msg.add_rff( :d1153=>'ON', :d1154=> nr1 )
      when 4
        @msg.add_rff( :d1153=>'DQ', :d1154=> nr1 )
      else
        raise "Kennzeichen LS/Auftrag (#{no}) ungueltig (Anm. 1): '#{kz}'"
      end
    end

    ls_auftrag_array.each do |a|
      kz, nr1, no = a
      case kz # Nr. 3, Anmerkung 3
      when 0  # empty - skip
      when 5  # Lieferscheinnummer
        @msg.add_rff( :d1153=>'DQ', :d1154=> nr1 )
      when 6  # Auftragsnummer
        @msg.add_rff( :d1153=>'ON', :d1154=> nr1 )
      else
        raise "Kennzeichen LS/Auftrag (#{no}) ungueltig (Anm. 3): '#{kz}'"
      end
    end # each

    # SG2: NAD-RFF
    #
    @msg.add_nad( :d3035=>'SU', :d3039=> shd.bbn_lieferant )
    @msg.add_rff( :d1153=>'VA', :d1154=> s01.v_nad_su_va )
    @msg.add_rff( :d1153=>'FC', :d1154=> s01.v_nad_su_fc )

    bbn = s01.v_nad_by
    bbn = shd.bbn_rechnungsempfaenger if bbn.nil? || bbn == 0 
    @msg.add_nad( :d3035=>'BY', :d3039=> bbn )
    @msg.add_rff( :d1153=>'VA', :d1154=> s01.v_nad_by_va )

    case kz=shd.warenempfaenger_kz
    when 1
      bbn = shd.bbn_warenempfaenger.to_s + "%06d" % shd.interne_nr
      @msg.add_nad( :d3035=>'DP', :d3039=> bbn )
    when 2
      s51 = master_data['51'].find{|s| s.refpos_nr == shd.positions_nr}
      raise "Sorry - SA51 fehlt fuer pos_nr={shd.positions_nr}" unless s51
      @msg.add_nad( :d3035=>'DP', :d3036_1=> s51.name_warenempfaenger,
                    :d3164=>   s51.ort,
                    :d3042_1=> s51.strasse_postfach,
                    :d3251=>   s51.plz_1==0 ? s51.plz_2.strip : s51.plz_1 )
      # @msg.add_rff( :d1153=>'IA', :d1154=> shd.interne_nr )
    when 3
      bbn = shd.bbn_warenempfaenger
      @msg.add_nad( :d3035=>'DP', :d3039=> bbn )
    else
      raise "Warenempfaenger-bbs: 'Kennzeichen' ungueltig: '#{kz}'"
    end

    # TAX-MOA SG6
    #
    all_str.each {|s| @msg.add_tax( :ust_kz=> s.ust_kz, :pos_nr=> s.positions_nr ) }

    # ALC-MOA SG16
    #
    all_str.each do |s|
      kz, betrag = s.fracht_verpackung_kz, s.fracht_verpackung
      next if kz == 0
      params = {}
      params[:d5463] = betrag > 0 ? 'C' : 'A'
      params[:d7161] = case kz
                       when 1: 'FC'
                       when 2: 'PC'
                       when 3: 'IN'
                       when 4,5,6,7: 'SH'
                         else raise "'Fracht/Verpackungs-Kennzeichen' ungueltig: '#{kz}'"
                       end
      @msg.add_alc( params )
      @msg.add_moa( :d5025=> 8, :d5004=> betrag.abs/100.0 )
    end

    all_str.each do |s|
      betrag = s.skonto
      next if betrag == 0
      @msg.add_alc( :d5463=> 'A', :d1227=> 1, :d7161=> 'EAB' )
      @msg.add_moa( :d5025=> 8,   :d5004=> betrag.abs/100.0 )
      summe_131 += betrag
      warn "Skonto positiv: #{s.skonto}, pos_nr=#{s.positions_nr}" if betrag>0
    end

    all_str.each do |s| # Also see code at item level, SG39
      [[s.rabatt_kz_1, s.nachweisrabatt_1, 1],
       [s.rabatt_kz_2, s.nachweisrabatt_2, 2],
       [s.rabatt_kz_3, s.nachweisrabatt_3, 3],
       [s.rabatt_kz_4, s.nachweisrabatt_4, 4]].each do |a|
        kz, betrag, no = a
        next if kz == 0

        params = {
          :d5463=> betrag < 0 ? 'A' : 'C', 
          :d7161=> 'DI', :d1227=> kz%10 - 1
        }
        params[:d1227] = nil unless params[:d1227].between?(1,4)
        @msg.add_alc( params )

        case (kz - kz%10)/10
        when 1..4, 6
          @msg.add_moa( :d5025=> 8, :d5004=> betrag.abs/100.0 )
        when 5
          @msg.add_moa( :d5025=> 8, :d5004=> betrag.abs/100.0 )
          pri_aab.d5125 = 'AAA' if pri_aab # Why?
        when 7
          @msg.add_pcd( :d5245=> 3, :d5482=> betrag.abs/10000.0 )
        when 8
          @msg.add_rte( :d5419=> 1, :d5420=> betrag.abs/10000.0 )
        else
          raise "ALC: Unbekanntes 'Rabatt-Kennzeichen: '#{kz}'"
        end
      end
    end

    # Items: Map elsewhere
    #
    s_msg[/[12][36]00/].each do |s|
      map_12_to_325_item( s.descendants_and_self, item_counter, master_data )
      item_counter += 2
    end

    # Trailer
    #
    uns = @msg.new_segment("UNS")
    uns.d0081 = 'S'
    @msg.add(uns)

    # MOA SG50
    #
    summe_402, summe_79, summe_77 = 0,0.0, 0
    # summe_131: siehe oben
    all_str.each do |s|
      if s.b_vereinbarung_kz_1 == 2 # Nr. 24
        summe_402 += s.b_vereinbarung_1
      end
      summe_131 += s.nachweisrabatt_gesamt
      summe_77  += s.nachweis_endbetrag
      if s.warenwert_kz == 1 # Nr. 11: 1=Warenwert
        summe_79 += to_value( s.komma_kz, s.warenbetrag_menge )
      end
    end
    @msg.add_moa( :d5025=> 402, :d5004=> summe_402/100.0 ) if summe_402 != 0
    @msg.add_moa( :d5025=> 131, :d5004=> summe_131/100.0 ) if summe_131 != 0
    @msg.add_moa( :d5025=>  79, :d5004=> summe_79 )
    @msg.add_moa( :d5025=>  77, :d5004=> summe_77 /100.0 ) if summe_77  != 0
    
    # TAX-MOA SG52, only if more than 1 STR record found
    #
    all_str.each do |s|
      @msg.add_tax( :ust_kz=> s.ust_kz, :pos_nr=> s.positions_nr )
      if s.warenwert_kz == 1 # Nr. 11: 1=Warenwert
        @msg.add_moa( :d5025=> 79, :d5004=> s.warenbetrag_menge/100.0 )
      end
      betrag = s.nachweisrabatt_gesamt + s.skonto
      @msg.add_moa( :d5025=> 131, :d5004=> betrag/100.0 ) if betrag != 0
    end if all_str.size > 1

    @p.add @msg, false
  end


  def map_12_to_325_item( segments, item_counter, master_data )
    # Lookahead / out-of-sequence segments first:
    ftx_in_item = []
    segments.find_all{|seg| seg.name=~/[12][36]08/}.each do |seg|
      ftx = @msg.new_segment("FTX")
      ftx.d4451 = 'ZZZ'
      ftx.cC108.a4440[0].value = seg.freitext.strip
      ftx.d3453 = 'DE'
      ftx_in_item << ftx
    end

    s02 = Verkettung02_Felder.new
    if seg=segments.find{|s| s.name=~/[12][36]02/} # just 0..1 expected
      s02.ust_prozentsatz = seg.ust_prozentsatz
      s02.preisschluessel = seg.preisschluessel
      s02.komma_kz_p = seg.komma_kz_p
      s02.grundpreis = seg.grundpreis
      s02.mengenschluessel = seg.mengenschluessel
      s02.komma_kz_m = seg.komma_kz_m
      s02.menge = seg.menge
      s02.empty = false
    else
      s02.empty = true
    end

    # Now do the serial mapping
    segments.each do |seg|

      seg_id = seg.name
      seg_id += ' ' + seg.sg_name if seg.sg_name
      case seg_id
      when /[12][36]00 SG1/
        # FIXME: Linear search - consider a hash for fast lookup via ean.
        s5000 = master_data.find{|s| s.name=='5000' && s.ean==seg.ean}
        raise "SA 50 fehlt fuer EAN #{seg.ean}, pos_nr=#{seg.positions_nr}" unless s5000

        @msg.add_lin( :d1082=> item_counter, :d7140=> seg.ean)

        # PIA
        #
        @msg.add_pia( :d4347=> 1, :d7140=> s5000.artikel_nr, :d7143=> 'SA')

        # IMD
        #
        @msg.add_imd( :d7077=> 'C', :d7009=> 'IN', :d7009_3055=> 9)
        @msg.add_imd( :d7077=> 'A', :d7008_1=> s5000.langtext)

        # QTY
        #
        if s02.empty || s02.mengenschluessel == 0 || s02.komma_kz_m == 0
          mengenschluessel, komma_kz_m, menge = 
            seg.mengenschluessel, seg.komma_kz_m, seg.menge
        else
          mengenschluessel, komma_kz_m, menge = 
            s02.mengenschluessel, s02.komma_kz_m, s02.menge
        end
        if s02.empty || s02.preisschluessel == 0 || s02.komma_kz_p == 0
          preisschluessel, komma_kz_p, grundpreis = 
            seg.preisschluessel, seg.komma_kz_p, seg.grundpreis
        else
          preisschluessel, komma_kz_p, grundpreis = 
            s02.preisschluessel, s02.komma_kz_p, s02.grundpreis
        end
        @msg.add_qty( :d6063=> preisschluessel == 9 ? 192 : 47, # w/o charge?
                      :d6060=> to_value( komma_kz_m, menge ),
                      :qkey=> mengenschluessel )

        # All FTX
        #
        ftx_in_item.each {|obj| @msg.add(obj)}

        # MOA
        #
        betrag = seg.artikelrabatt_gesamt
        @msg.add_moa( :d5025=> 131, :d5004=> betrag/100.0 ) if betrag != 0
        betrag = seg.warenwert
        @msg.add_moa( :d5025=> 203, :d5004=> betrag/100.0 ) if betrag != 0
        if seg.b_vereinbarung_kz_2 == 3
          @msg.add_moa( :d5025=> 204, :d5004=> seg.b_vereinbarung_2/10.0 )
        end

        # PRI
        #
        pri_aab =
          @msg.add_pri(:d5125=>'AAB', :d5118=>to_value( komma_kz_p,grundpreis),
                       :pkey=>preisschluessel, :qkey=>mengenschluessel )
        if seg.schluessel_kz == 1
          @msg.add_pri( :d5125=>'AAE',
                        :d5118=>to_value( seg.komma_kz, seg.sondereintrag ) )
                        # :pkey=>preisschluessel, :qkey=>mengenschluessel)
        elsif seg.schluessel_kz == 3
          @msg.add_pri( :d5125=>'AAA',
                        :d5118=>to_value( seg.komma_kz, seg.sondereintrag ) )
        end

        # RFF-DTM SG30
        #
        if seg.b_vereinbarung_kz_2 == 5
          @msg.add_rff( :d1153=>'AAK', :d1154=> seg.b_vereinbarung_2 )
        end

        # TAX-MOA
        #
        @msg.add_tax( :ust_kz=> seg.umsatzsteuer_kz, :pos_nr=> seg.positions_nr )


        # ALC SG39
        #
        [[seg.rabatt_kz_1, seg.artikelrabatt_1, 1],
         [seg.rabatt_kz_2, seg.artikelrabatt_2, 2],
         [seg.rabatt_kz_3, seg.artikelrabatt_3, 3],
         [seg.rabatt_kz_4, seg.artikelrabatt_4, 4]].each do |a|
          kz, betrag, no = a
          next if kz == 0

          params = {
            :d5463=> betrag < 0 ? 'A' : 'C', 
            :d7161=> 'DI', :d1227=> kz%10 - 1
          }
          params[:d1227] = nil unless params[:d1227].between?(1,4)
          @msg.add_alc( params )

          case (kz - kz%10)/10
          when 1..4, 6
            @msg.add_moa( :d5025=> 8, :d5004=> betrag.abs/100.0 )
          when 5
            @msg.add_moa( :d5025=> 8, :d5004=> betrag.abs/100.0 )
            pri_aab.d5125 = 'AAA' if pri_aab # Why?
          when 7
            @msg.add_pcd( :d5245=> 3, :d5482=> betrag.abs/10000.0 )
          when 8
            @msg.add_rte( :d5419=> 1, :d5420=> betrag.abs/10000.0 )
          else
            raise "ALC: Unbekanntes 'Rabatt-Kennzeichen: '#{kz}'"
          end
        end

        # Sub-line info
        #
        @msg.add_lin( :d1082=> item_counter+1, 
                      :d7140=> s5000.kleinste_ean,
                      :c829_d1082 => item_counter )

        @msg.add_pia( :d4347=> 1, :d7140=> "%04d" % s5000.klassifikation,
                      :d7143=> 'GN')
        @msg.add_imd( :d7077=> 'C', :d7009=> 'CU', :d7009_3055=> 9)
        @msg.add_qty( :d6063=> 59, :d6060=> s5000.menge_ean )

          
      when /[12][36]0[28] SG1/
        # ignored here - handled by lookahead section

      else
        raise "Segment-Id #{seg_id} hier nicht erwartet!"
      end
    end
  end


  def map_15_to_38x( s_msg, master_data )
    @msg = @p.new_message( @msg_params )
    item_counter = 1

    # Lookahead / out-of-sequence segments first:
    #
    ftx_in_header = []
    # 08 for SA 12/22, 15/25
    s_msg[/[12][25]08/].each do |seg|
      ftx = @msg.new_segment("FTX")
      ftx.d4451 = 'ZZZ'
      ftx.cC108.a4440[0].value = seg.freitext.strip
      ftx.d3453 = 'DE'
      ftx_in_header << ftx
    end
    # 08 for SA 14/24, 17/27
    s_msg[/[12][47]08/].each do |seg|
      ftx = @msg.new_segment("FTX")
      ftx.d4451 = 'SUR'
      ftx.cC108.a4440[0].value = seg.freitext.strip
      ftx.d3453 = 'DE'
      ftx_in_header << ftx
    end

    s01 = Verkettung01_Felder.new
    if seg=s_msg[/[12][25]01/].first # 1201, 2201, 1501, 2501
      s01.v_nad_by = seg.bbn_rechnungsempfaenger
      s01.v_nad_ds = seg.bbn_warenlieferant
      s01.v_nad_su_va = seg.ust_ident_nr_lieferant
      s01.v_nad_su_fc = seg.steuer_nr
      s01.v_nad_by_va = seg.ust_ident_nr_erwerber
      s01.ls_a_kz = seg.ls_auftrag_kz
      s01.ls_a_nr1 = seg.ls_auftrag_nr_1
      s01.ls_a_nr2 = seg.ls_auftrag_nr_2
    else
      s01.ls_a_kz = 0
    end

    # Naming convention:
    #
    # shd = SEDAS header  record, e.g. a SA12/22 or a SA15/25
    # str = SEDAS trailer record, e.g. a SA14/24 or a SA17/27
    #
    shd = s_msg[/[12][25]00/].first # Must exist due to SEDAS msg definition!
    all_str = s_msg[/[12][47]00/]   # Expect one per VAT rate, one at least

    ls_auftrag_array = [[shd.ls_auftrag_kz_1, shd.ls_auftrag_nr_1, 1],
                        [shd.ls_auftrag_kz_2, shd.ls_auftrag_nr_2, 2],
                        [shd.ls_auftrag_kz_3, shd.ls_auftrag_nr_3, 3],
                        [shd.ls_auftrag_kz_4, shd.ls_auftrag_nr_4, 4],
                        [shd.ls_auftrag_kz_5, shd.ls_auftrag_nr_5, 5]]

    summe_77 = all_str.inject(0){|sum, s| sum + s.endbetrag}
    summe_131 = 0     # Evtl. erst Skonto addieren, siehe ALC (EAB)
    vz = summe_77<=>0 # Vorzeichen, Unterscheidung Rechnung(+1)/Gutschrift(-1)

    # BGM
    #
    bgm = @msg.new_segment("BGM")
    bgm.cC002.d1001 = (vz < 0) ? 381 : 380
    bgm.cC106.d1004 = shd.beleg_nr
    bgm.d1225 = 9
    @msg.add(bgm)

    # All DTM
    #
    @msg.add_dtm(:d2005=> 137, :digits=> 5, :d2380=>shd.datum_rechnung)
    if shd.lieferdatum==0
      warn "Re-Nr #{shd.beleg_nr}, Pos-Nr #{shd.positions_nr}: " + 
        "Lieferdatum fehlt - verwende Belegdatum!"
      @msg.add_dtm(:d2005=>  35, :d2380=> shd.datum_rechnung)
    else
      @msg.add_dtm(:d2005=>  35, :d2380=> shd.lieferdatum)
    end

    [
     [shd.ls_auftrag_kz, shd.ls_auftrag_nr, shd.auftrags_nr_besteller, 1],
     [s01.ls_a_kz, s01.ls_a_nr1, s01.ls_a_nr2, 2]
    ].each do |a|
      kz, nr1, nr2, no = a
      next unless kz==2 # Lieferdatum von-bis (0JJMMTT)
      dt = if nr1.is_a? String
             @curr_year[0,2]+nr1[1,6]+@curr_year[0,2]+nr2[1,6]
           else
             @curr_year[0,2]+"%06d" % nr1 + @curr_year[0,2]+"%06d" % nr2
           end
      @msg.add_dtm( :d2005=>35, :d2380=>dt, :d2379=>718 ) # CCYYMMDD-CCYYMMDD
    end

    # ALI
    #
    # Anmerkung 18:
    if shd.b_vereinbarung_kz_1==6 || shd.b_vereinbarung_kz_2==6
      ali = @msg.new_segment("ALI")
      bgm.a4183[0].value = 15
      @msg.add ali
    end
    # FIXME: Trap case "b_vereinbarung_kz_x != 1 or 6

    # All FTX
    #
    ftx_in_header.each {|obj| @msg.add(obj)}

    # SG1: RFF-DTM
    #
    case q=shd.reli_zahlungsempfaenger_kz  # Nr. 2, Anmerkung 17
    when 0 # empty - skip
    when 1
      @msg.add_rff( :d1153=>'ABO', :d1154=> shd.rz_eintrag_1 )
      @msg.add_dtm( :d2005=> 171,  :d2380=> shd.rz_eintrag_2 )
    when 2
      @msg.add_rff( :d1153=>'ABO', :d1154=> shd.rz_eintrag_1 )
    when 6
      @msg.add_rff( :d1153=>'IV', :d1154=> shd.rz_eintrag_1 )
      @msg.add_dtm( :d2005=> 171, :d2380=> shd.rz_eintrag_2 )
    when 7
      @msg.add_rff( :d1153=>'IV', :d1154=> shd.rz_eintrag_1 )
    else
      raise "S.-Rechnung: 'Kennzeichen' ungueltig: #{q}"
    end

    [
     [shd.ls_auftrag_kz, shd.ls_auftrag_nr, shd.auftrags_nr_besteller, 1],
     [s01.ls_a_kz, s01.ls_a_nr1, s01.ls_a_nr2, 2]
    ].each do |a|
      kz, nr1, nr2, no = a
      case kz  # Nr. 3, Anmerkung 1
      when nil # treat as empty, should not occur
        $log.warn("ls_auftrag_kz (#{no}) fehlt!")
      when 0   # empty - skip
      when 1
        @msg.add_rff( :d1153=>'DQ', :d1154=> nr1 )
        @msg.add_rff( :d1153=>'ON', :d1154=> nr2 )
      when 2   # skip - treated earlier (DTM)
      when 3
        @msg.add_rff( :d1153=>'ON', :d1154=> nr1 )
      when 4
        @msg.add_rff( :d1153=>'DQ', :d1154=> nr1 )
      else
        raise "Kennzeichen LS/Auftrag (#{no}) ungueltig (Anm. 1): '#{kz}'"
      end
    end

    ls_auftrag_array.each do |a|
      kz, nr1, no = a
      case kz # Nr. 3, Anmerkung 3
      when 0  # empty - skip
      when 5  # Lieferscheinnummer
        @msg.add_rff( :d1153=>'DQ', :d1154=> nr1 )
      when 6  # Auftragsnummer
        @msg.add_rff( :d1153=>'ON', :d1154=> nr1 )
      else
        raise "Kennzeichen LS/Auftrag (#{no}) ungueltig (Anm. 3): '#{kz}'"
      end
    end # each

    # SG2: NAD-RFF
    #
    @msg.add_nad( :d3035=>'SU', :d3039=> shd.bbn_lieferant )
    @msg.add_rff( :d1153=>'VA', :d1154=> s01.v_nad_su_va )
    @msg.add_rff( :d1153=>'FC', :d1154=> s01.v_nad_su_fc )

    bbn = s01.v_nad_by
    bbn = shd.bbn_rechnungsempfaenger if bbn.nil? || bbn == 0 
    @msg.add_nad( :d3035=>'BY', :d3039=> bbn )
    @msg.add_rff( :d1153=>'VA', :d1154=> s01.v_nad_by_va )
    # Anmerkung 18:
    @msg.add_rff( :d1153=>'YC1',:d1154=> shd.b_vereinbarung_1 ) if
      shd.b_vereinbarung_kz_1 == 1
    @msg.add_rff( :d1153=>'YC1',:d1154=> shd.b_vereinbarung_2 ) if
      shd.b_vereinbarung_kz_2 == 1

    case kz=shd.warenempfaenger_kz
    when 1
      bbn = shd.bbn_warenempfaenger.to_s + "%06d" % shd.interne_nr
      @msg.add_nad( :d3035=>'DP', :d3039=> bbn )
    when 2
      s51 = master_data['51'].find{|s| s.refpos_nr == shd.positions_nr}
      raise "Sorry - SA51 fehlt fuer pos_nr={shd.positions_nr}" unless s51
      @msg.add_nad( :d3035=>'DP', :d3036_1=> s51.name_warenempfaenger,
                    :d3164=>   s51.ort,
                    :d3042_1=> s51.strasse_postfach,
                    :d3251=>   s51.plz_1==0 ? s51.plz_2.strip : s51.plz_1 )
      # @msg.add_rff( :d1153=>'IA', :d1154=> shd.interne_nr )
    when 3
      bbn = shd.bbn_warenempfaenger
      @msg.add_nad( :d3035=>'DP', :d3039=> bbn )
    else
      raise "Warenempfaenger-bbs: 'Kennzeichen' ungueltig: '#{kz}'"
    end

    # TAX-MOA SG6
    #
    all_str.each {|s| @msg.add_tax( :ust_kz=> s.ust_kz, :pos_nr=> s.positions_nr ) }

    # ALC-MOA SG16
    #
    all_str.each do |s|
      kz, betrag = s.fracht_verpackung_kz, s.frachtbelastung
      next if kz == 0
      params = {}
      params[:d5463] = betrag > 0 ? 'C' : 'A'
      params[:d7161] = case kz
                       when 1: 'FC'
                       when 2: 'PC'
                       when 3: 'IN'
                       when 4,5,6,7: 'SH'
                         else raise "'Fracht/Verpackungs-Kennzeichen' ungueltig: '#{kz}'"
                       end
      @msg.add_alc( params )
      @msg.add_moa( :d5025=> 8, :d5004=> betrag.abs/100.0 )
    end

    all_str.each do |s|
      betrag = s.skonto
      next if betrag == 0
      @msg.add_alc( :d5463=> 'A', :d1227=> 1, :d7161=> 'EAB' )
      @msg.add_moa( :d5025=> 8,   :d5004=> betrag.abs/100.0 )
      summe_131 += betrag
      warn "Skonto positiv: #{betrag}, pos_nr=#{s.positions_nr}" if vz*betrag>0
    end

    all_str.each do |s| # Also see code at item level, SG39
      [[s.rabatt_kz_1, s.rechnungsrabatt_1, 1],
       [s.rabatt_kz_2, s.rechnungsrabatt_2, 2],
       [s.rabatt_kz_3, s.rechnungsrabatt_3, 3],
       [s.rabatt_kz_4, s.rechnungsrabatt_4, 4]].each do |a|
        kz, betrag, no = a
        next if kz == 0

        params = {
          :d5463=> betrag < 0 ? 'A' : 'C',
          :d7161=> 'DI', :d1227=> kz%10 - 1
        }
        params[:d1227] = nil unless params[:d1227].between?(1,4)
        @msg.add_alc( params )

        case (kz - kz%10)/10
        when 1..4, 6
          @msg.add_moa( :d5025=> 8, :d5004=> betrag.abs/100.0 )
        when 5
          @msg.add_moa( :d5025=> 8, :d5004=> betrag.abs/100.0 )
          pri_aab.d5125 = 'AAA' if pri_aab # Why?
        when 7
          @msg.add_pcd( :d5245=> 3, :d5482=> betrag.abs/10000.0 )
        when 8
          @msg.add_rte( :d5419=> 1, :d5420=> betrag.abs/10000.0 )
        else
          raise "ALC: Unbekanntes 'Rabatt-Kennzeichen: '#{kz}'"
        end
      end
    end

    # Items: Map elsewhere
    #
    s_msg[/[12][36]00/].each do |s|
      map_16_to_38x_item( s.descendants_and_self, item_counter, 
                          master_data, vz )
      item_counter += 2
    end

    # Trailer
    #
    uns = @msg.new_segment("UNS")
    uns.d0081 = 'S'
    @msg.add(uns)

    # MOA SG50
    #
    summe_402, summe_124, summe_79 = 0, 0, 0
    # summe_77, summe_131: siehe oben
    all_str.each do |s|
      if s.b_vereinbarung_kz_1 == 2 # Nr. 27
        summe_402 += s.b_vereinbarung_1
      end
      # FIXME: Really try to add both occurrences?
      if s.b_vereinbarung_kz_2 == 2 # Nr. 27
        summe_402 += s.b_vereinbarung_2
      end
      summe_124 += s.umsatzsteuer
      summe_131 += s.rechnungsrabatt_gesamt
      summe_79  += s.warenbetrag
      # summe_77  += s.endbetrag # See beginning
    end
    @msg.add_moa( :d5025=> 402, :d5004=> vz*summe_402/100.0 ) if summe_402 != 0
    @msg.add_moa( :d5025=> 131, :d5004=> vz*summe_131/100.0 ) if summe_131 != 0
    @msg.add_moa( :d5025=> 125, :d5004=> vz*(summe_77 - summe_124)/100.0 )
    @msg.add_moa( :d5025=> 124, :d5004=> vz*summe_124/100.0 ) if summe_124 != 0
    @msg.add_moa( :d5025=>  79, :d5004=> vz*summe_79 /100.0 ) if summe_79  != 0
    @msg.add_moa( :d5025=>  77, :d5004=> vz*summe_77 /100.0 ) if summe_77  != 0
    
    # TAX-MOA SG52, only if more than 1 trailer record found
    #
    all_str.each do |s|
      if s.ust_kz != 0 # Nr. 9
        @msg.add_tax( :ust_kz=> s.ust_kz, :pos_nr=> s.positions_nr )
        @msg.add_moa( :d5025=> 79,  :d5004=> vz*s.warenbetrag/100.0 )
        @msg.add_moa( :d5025=> 124, :d5004=> vz*s.umsatzsteuer/100.0 )
        betrag = s.rechnungsrabatt_gesamt + s.skonto
        @msg.add_moa( :d5025=> 131, :d5004=> vz*betrag/100.0 ) if betrag != 0
      end
    end if all_str.size > 1

    @p.add @msg, false
  end


  def map_16_to_38x_item( segments, item_counter, master_data, vz )
    # Lookahead / out-of-sequence segments first:
    ftx_in_item = []
    segments.find_all{|seg| seg.name=~/[12][36]08/}.each do |seg|
      ftx = @msg.new_segment("FTX")
      ftx.d4451 = 'ZZZ'
      ftx.cC108.a4440[0].value = seg.freitext.strip
      ftx.d3453 = 'DE'
      ftx_in_item << ftx
    end

    s02 = Verkettung02_Felder.new
    if seg=segments.find{|s| s.name=~/[12][36]02/} # just 0..1 expected
      s02.ust_prozentsatz = seg.ust_prozentsatz
      s02.preisschluessel = seg.preisschluessel
      s02.komma_kz_p = seg.komma_kz_p
      s02.grundpreis = seg.grundpreis
      s02.mengenschluessel = seg.mengenschluessel
      s02.komma_kz_m = seg.komma_kz_m
      s02.menge = seg.menge
      s02.empty = false
    else
      s02.empty = true
    end

    # Now do the serial mapping
    segments.each do |seg|

      seg_id = seg.name
      seg_id += ' ' + seg.sg_name if seg.sg_name
      case seg_id
      when /[12][36]00 SG1/
        # FIXME: Linear search - consider a hash for fast lookup via ean.
        s5000 = master_data.find{|s| s.name=='5000' && s.ean==seg.ean}
        raise "SA 50 fehlt fuer EAN #{seg.ean}, pos_nr=#{seg.positions_nr}" unless s5000

        @msg.add_lin( :d1082=> item_counter, :d7140=> seg.ean)

        # PIA
        #
        @msg.add_pia( :d4347=> 1, :d7140=> s5000.artikel_nr, :d7143=> 'SA')

        # IMD
        #
        @msg.add_imd( :d7077=> 'C', :d7009=> 'IN', :d7009_3055=> 9)
        @msg.add_imd( :d7077=> 'A', :d7008_1=> s5000.langtext)

        # QTY
        #
        if s02.empty || s02.mengenschluessel == 0 || s02.komma_kz_m == 0
          mengenschluessel, komma_kz_m, menge = 
            seg.mengenschluessel, seg.komma_kz_m, seg.menge
        else
          mengenschluessel, komma_kz_m, menge = 
            s02.mengenschluessel, s02.komma_kz_m, s02.menge
        end
        if s02.empty || s02.preisschluessel == 0 || s02.komma_kz_p == 0
          preisschluessel, komma_kz_p, grundpreis = 
            seg.preisschluessel, seg.komma_kz_p, seg.grundpreis
        else
          preisschluessel, komma_kz_p, grundpreis = 
            s02.preisschluessel, s02.komma_kz_p, s02.grundpreis
        end
        @msg.add_qty( :d6063=> preisschluessel == 9 ? 192 : 47, # w/o charge?
                      :d6060=> to_value( komma_kz_m, vz*menge ),
                      :qkey=> mengenschluessel )

        # All FTX
        #
        ftx_in_item.each {|obj| @msg.add(obj)}

        # MOA
        #
        betrag = seg.artikelrabatt_gesamt
        @msg.add_moa( :d5025=> 131, :d5004=> vz*betrag/100.0 ) if betrag != 0
        betrag = seg.warenwert
        @msg.add_moa( :d5025=> 203, :d5004=> vz*betrag/100.0 ) if betrag != 0
        if seg.b_vereinbarung_kz_2 == 3
          @msg.add_moa( :d5025=> 204, :d5004=> vz*seg.b_vereinbarung_2/10.0 )
        end

        # PRI
        #
        pri_aab =
          @msg.add_pri(:d5125=>'AAB', :d5118=>to_value( komma_kz_p,grundpreis),
                       :pkey=>preisschluessel, :qkey=>mengenschluessel )
        if seg.schluessel_kz == 1
          @msg.add_pri( :d5125=>'AAE',
                        :d5118=>to_value( seg.komma_kz, seg.sondereintrag ) )
                        # :pkey=>preisschluessel, :qkey=>mengenschluessel)
        elsif seg.schluessel_kz == 3
          @msg.add_pri( :d5125=>'AAA',
                        :d5118=>to_value( seg.komma_kz, seg.sondereintrag ) )
        end

        # RFF-DTM SG30
        #
        if seg.b_vereinbarung_kz_2 == 5
          @msg.add_rff( :d1153=>'AAK', :d1154=> seg.b_vereinbarung_2 )
        end

        # TAX-MOA
        #
        @msg.add_tax( :ust_kz=> seg.umsatzsteuer_kz, :pos_nr=> seg.positions_nr )


        # ALC SG39
        #
        [[seg.rabatt_kz_1, seg.artikelrabatt_1, 1],
         [seg.rabatt_kz_2, seg.artikelrabatt_2, 2],
         [seg.rabatt_kz_3, seg.artikelrabatt_3, 3],
         [seg.rabatt_kz_4, seg.artikelrabatt_4, 4]].each do |a|
          kz, betrag, no = a
          next if kz == 0

          params = {
            :d5463=> betrag < 0 ? 'A' : 'C',
            :d7161=> 'DI', :d1227=> kz%10 - 1
          }
          params[:d1227] = nil unless params[:d1227].between?(1,4)
          @msg.add_alc( params )

          case (kz - kz%10)/10
          when 1..4, 6
            @msg.add_moa( :d5025=> 8, :d5004=> betrag.abs/100.0 )
          when 5
            @msg.add_moa( :d5025=> 8, :d5004=> betrag.abs/100.0 )
            pri_aab.d5125 = 'AAA' if pri_aab # Why?
          when 7
            @msg.add_pcd( :d5245=> 3, :d5482=> betrag.abs/10000.0 )
          when 8
            @msg.add_rte( :d5419=> 1, :d5420=> betrag.abs/10000.0 )
          else
            raise "ALC: Unbekanntes 'Rabatt-Kennzeichen: '#{kz}'"
          end
        end

        # Sub-line info
        #
        @msg.add_lin( :d1082=> item_counter+1, 
                      :d7140=> s5000.kleinste_ean,
                      :c829_d1082 => item_counter )

        @msg.add_pia( :d4347=> 1, :d7140=> "%04d" % s5000.klassifikation,
                      :d7143=> 'GN')
        @msg.add_imd( :d7077=> 'C', :d7009=> 'CU', :d7009_3055=> 9)
        @msg.add_qty( :d6063=> 59, :d6060=> s5000.menge_ean )

          
      when /[12][36]0[2468] SG1/
        # ignored here - handled by lookahead section

      else
        raise "Segment-Id #{seg_id} hier nicht erwartet!"
      end
    end
  end


  def map_29_to_393( s_msg )
    @msg = @p.new_message( @msg_params )

    raise "Verkettung 01 zu SA29 nicht unterstuetzt - sorry" unless s_msg['2901'].empty?
    raise "Verkettung 02 zu SA29 nicht unterstuetzt - sorry" unless s_msg['2902'].empty?

    all_s29 = s_msg['2900']
    s29 = all_s29.first # Must exist due to SEDAS msg definition!
    
    bgm = @msg.new_segment("BGM")
    bgm.cC002.d1001 = 393
    raise "Erste SA29 muss eine 'Rechnungslistennummer' enthalten!" unless s29.reli_kz == 2
    bgm.cC106.d1004 = s29.nummer
    bgm.d1225 = 9
    @msg.add(bgm)

    @msg.add_dtm(:d2005=> 137, :digits=> 5, :d2380=>s29.datum_reli)

    # SG1: RFF-DTM
    #
    if (nr=s29.abkommen_nr) != 0
      @msg.add_rff( :d1153=>'CT', :d1154=> nr )
    end

    # SG2: NAD group
    #
    @msg.add_nad( :d3035=>'SU', :d3039=> s29.bbn_lieferant )
    @msg.add_nad( :d3035=>'BY', :d3039=> s29.bbn_rechnungslistenempfaenger )
    @msg.add_nad( :d3035=>'PE', :d3039=> s29.bbn_zahlungsempfaenger )
    @msg.add_nad( :d3035=>'PR', :d3039=> s29.bbn_zahlungsleistender )


    # TAX-MOA SG6
    #
    @msg.add_tax( :ust_kz=> s29.ust_kz, :pos_nr=> s29.positions_nr )
    # Just first occurrence of SA29 ok?

    # PAT-DTM SG8
    #
    if (vdat=s29.valutadatum) != 0
      @msg.add_pat( :d4279=> 3 )
      @msg.add_dtm( :d2005=> 209, :d2380=> vdat )
    end
    

    # Trailer
    #
    uns = @msg.new_segment("UNS")
    uns.d0081 = 'S'
    @msg.add(uns)

    # MOA SG50
    #

    summe_124, summe_125, summe_86 = summe_9 = 0, 0, 0, 0
    all_s29.each do |s|
      summe_124 += s.umsatzsteuer
      summe_86  += s.endbetrag
      summe_9   += s.zahlbetrag
    end
    @msg.add_moa( :d5025=>  86, :d5004=> summe_86 /100.0 )
    @msg.add_moa( :d5025=>   9, :d5004=> summe_9  /100.0 )
    @msg.add_moa( :d5025=> 124, :d5004=> summe_124/100.0 )
    @msg.add_moa( :d5025=> 125, :d5004=> (summe_86 - summe_124)/100.0 )

    
    # TAX-MOA SG52, only if more than 1 S29 record found
    #
    all_s29.each do |s|
      @msg.add_tax( :ust_kz=> s.ust_kz, :pos_nr=> s.positions_nr )
      @msg.add_moa( :d5025=> 124, :d5004=> s.umsatzsteuer/100.0 )
      @msg.add_moa( :d5025=> 125, :d5004=> (s.zahlbetrag - s.umsatzsteuer)/100.0 )
      @msg.add_moa( :d5025=>  86, :d5004=> s.endbetrag/100.0 )
    end if all_s29.size > 1
    
    @p.add @msg
  end


  def initialize(src, dest)
    @msg = nil
    @with_ung = false
    @s = src
    @ic = dest
    @p = @ic # Current parent of a message - either the interchange or a group
    @msg_params = {
      :msg_type => 'INVOIC', 
      :version => 'D', 
      :release => '01B', 
      :resp_agency => 'UN',
      :assigned_code => 'EAN010'
    }
    @curr_year = Time.now.year.to_s
  end


  def go
    map_00_to_unb(@s.header)
    @s.each do |grp|
      map_01_to_ung(grp.header) if self.with_ung
      master_data = grp.find {|msg| msg.name=='50'}
      grp.each do |msg|
        case msg.name
        when '12', '22'
          map_12_to_325( msg, master_data )
        when '15', '25'
          map_15_to_38x( msg, master_data )
        when '29'
          map_29_to_393( msg )
        when '50'
          # Skip master data
        else
          raise "SA#{msg.name} nicht unterstuetzt - sorry"
        end
      end
    end
  end


  def validate
    @ic.validate
  end
  
  def write(hnd)
    @ic.write(hnd)
  end
end


#
# MAIN
#

$log = Logger.new(STDERR)
$log.level = Logger::INFO
$log.datetime_format = "%H:%M:%S"

params = {
  :show_una => true,
  :charset => 'UNOC', 
  :version => 3,
  :interchange_control_reference => Time.now.to_f.to_s[0...14] ,
  # :application_reference => 'EANCOM' ,
  # :output_mode => :verbatim,
  # :acknowledgment_request => true,
  :interchange_agreement_id => 'EANCOM'+'' , # your ref here!
  :test_indicator => 1,
}
ic = EDI::E::Interchange.new( params )


with_ung = false

while ARGV[0] =~ /^-(\w)/
  opt = ARGV.shift
  case $1
  when 'v' # verbose mode - here: use formatted output
    ic.output_mode = :indented
  when 'g'
    with_ung = true
  else
    raise "Option nicht zulaessig: #{opt}"
  end
end

$log.info "Input einlesen..."
sedas_ic = EDI::S::Interchange.parse(File.open(ARGV[0], 'r'), false)
$log.info  "Input validieren..."
sedas_ic.validate
$log.info  "Zuordnen..."
map = SEDAS_to_EANCOM02_Map_INVOIC.new( sedas_ic, ic )
#
# Add UNG/UNE if there is more than one group per file
#
map.with_ung = (sedas_ic.size > 1) # with_ung
map.go
$log.info "Output validieren..."
ic.validate
$log.info  "Ergebnis schreiben..."
$stdout.write ic
$log.info  "Fertig."
# ic.inspect
