#!/usr/bin/env ruby
# -*- encoding: iso-8859-1 -*-
# :include: ../AuthorCopyright

# Load path magic...
$:.unshift File.join(File.dirname(__FILE__), '..', 'lib')

require 'test/unit'

require 'edi4r'
# require 'edi4r-tdid'
require 'edi4r/edifact'

class EDIFACT_Tests < Test::Unit::TestCase

  # edi@energy sample:
  # UCI+10001+4078901000029:14+4012345000023:14+4'
  # Dieses Beispiel identifiziert die Übertragung 10001 vom Absender
  # 4078901000029 (ILN) an den Empfänger 4012345000023 (ILN). 
  # In der empfangenen Datei wurde ein Syntaxfehler festgestellt.

  def fill_CONTRL( msg )
    seg = msg.new_segment('UCI')
    msg.add seg
    seg.d0020 = '10001'
    seg.cS002.d0004 = '4078901000029'
    seg.cS002.d0007 = '14'
    seg.cS003.d0010 = '4012345000023'
    seg.cS003.d0007 = '14'
    seg.d0083 = '4'
  end

  # Sample data from EANCOM 2002 example 2:
  #
  # UNH+AUT0001+AUTACK:4:1:UN:EAN001'
  # USH+7+1+3+1+2+1++++1:20020102:100522:0100'
  # USA+1:16:1:6:1:7:1'
  # USC+AXZ4711+4::541234500006:2+3'
  # USA+6:16:1:10:1:7:1'
  # USB+1++5412345678908:14+8798765432106:14'
  # USX+INT12435+5412345678908:14+8798765432106:14'
  # USY+1+1:139B7CB..........7C72B03CE5F'
  # UST+1+5'
  # UNT+10+AUT0001
  #
  def fill_AUTACK( msg )
    msg.header.d0062 = 'AUT0001'

    seg = msg.new_segment('USH')
    msg.add seg
    seg.d0501 = 7
    seg.d0534 = 1
    seg.d0541 = 3
    seg.d0503 = 1
    seg.d0505 = 2
    seg.d0507 = 1
    seg.cS501.d0517 = 1
    seg.cS501.d0338 = '20020102'
    seg.cS501.d0314 = '100522'
    seg.cS501.d0336 = '0100'

    seg = msg.new_segment('USA')
    msg.add seg
    seg.cS502.d0523 = 1
    seg.cS502.d0525 = 16
    seg.cS502.d0533 = 6
    seg.cS502.d0527 = 1
    seg.cS502.d0529 = 6
    seg.cS502.d0591 = 7
    seg.cS502.d0601 = 1

    seg = msg.new_segment('USC')
    msg.add seg
    seg.d0536 = 'AXZ4711'
    seg.cS500.d0577 = 4
    seg.cS500.d0511 = '541234500006'
    seg.cS500.d0513 = 2
    seg.d0545 = 3

    seg = msg.new_segment('USA')
    msg.add seg
    seg.cS502.d0523 = 6
    seg.cS502.d0525 = 16
    seg.cS502.d0533 = 1
    seg.cS502.d0527 = 10
    seg.cS502.d0529 = 1
    seg.cS502.d0591 = 7
    seg.cS502.d0601 = 1

    seg = msg.new_segment('USB')
    msg.add seg
    seg.d0503 = 1
    seg.cS002.d0004 = '5412345678908'
    seg.cS002.d0007 = 14
    seg.cS003.d0010 = '8798765432106'
    seg.cS003.d0007 = 14

    seg = msg.new_segment('USX')
    msg.add seg
    seg.d0020 = 'INT12435'
    seg.cS002.d0004 = '5412345678908'
    seg.cS002.d0007 = 14
    seg.cS003.d0010 = '8798765432106'
    seg.cS003.d0007 = 14

    seg = msg.new_segment('USY')
    msg.add seg
    seg.d0534 = 1
    seg.cS508.d0563 = 1
    seg.cS508.d0560 = '139B7CB..........7C72B03CE5F'

    seg = msg.new_segment('UST')
    msg.add seg
    seg.d0534 = 1
    seg.d0588 = 5
  end



  def test_CONTRL_creation

    test_set = [
	    {:sv => 2, :version => '2', :release => '2'}, # Can't work - segments missing?
	    {:sv => 3, :version => 'D', :release => '3'},
	    {:sv => 3, :version => 'D', :release => '3', :assigned_code => '1.3c'},
#	    {:sv => 3, :version => 'D', :release => '96A', :assigned_code => 'EAN002'},
    ]
    test_set.each do |testcase|
      ic = nil
      assert_nothing_raised { ic = EDI::E::Interchange.new(
	      :version => testcase[:sv],
	      :charset => testcase[:sv] == 2 ? 'UNOB' : 'UNOC') }
      ic.header.d0035 = 1  # Test indicator
      msg = ic.new_message(:msg_type => 'CONTRL',
			   :version => testcase[:version],
			   :release => testcase[:release],
     			   :assigned_code => testcase[:assigned_code])
      fill_CONTRL(msg)
      ic.add msg
      assert_equal( 1, msg.header.first.value ) # value of DE 0062
      s009 = ['CONTRL', testcase[:version], testcase[:release], 'UN'].join ic.una.ce_sep
      s009 << ":#{testcase[:assigned_code]}" unless testcase[:assigned_code].nil?
      assert_equal( s009, msg.header[1].to_s ) # S009
      assert_equal( ['UNH', 1, s009].join(ic.una.de_sep), msg.header.to_s ) # UNH
#     puts ic
    end
  end

  def test_AUTACK_creation

    test_set = [
	    {:sv => 4, :version => '4', :release => '1'},
	    {:sv => 4, :version => '4', :release => '1', :assigned_code => 'EAN008'},
	    {:sv => 3, :version => '4', :release => '1', :should_fail => true}
    ]
    test_set.each do |testcase|
      ic = nil
      assert_nothing_raised { ic = EDI::E::Interchange.new(
	      :version => testcase[:sv], :charset => 'UNOA') }
      unb = ic.header 
      unb.d0020 = 'INT12435'
      unb.cS002.d0004 = '5412345678908'
      unb.cS002.d0007 = 14
      unb.cS003.d0010 = '8798765432106'
      unb.cS003.d0007 = 14
      msg = ic.new_message(:msg_type => 'AUTACK',
			   :version => testcase[:version],
			   :release => testcase[:release],
     			   :assigned_code => testcase[:assigned_code])
      if testcase[:should_fail]
        assert_raise(RuntimeError, EDI::EDILookupError) do
	  fill_AUTACK(msg) # Lookup error?
	  ic.add msg       # Validation error?
	end
      else
        assert_nothing_raised do
	  fill_AUTACK(msg)
	  ic.add msg
	end
      end

      assert_equal( 'AUT0001', msg.header.first.value ) # value of DE 0062
      s009 = "AUTACK:#{testcase[:version]}:#{testcase[:release]}:UN"
      s009 << ":#{testcase[:assigned_code]}" unless testcase[:assigned_code].nil?
      assert_equal( s009, msg.header[1].to_s ) # S009
      assert_equal( "UNH+AUT0001+"+s009, msg.header.to_s ) # UNH
    end
  end

end
