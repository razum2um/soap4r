=begin
SOAP4R - SOAP Dynamic EncodingStyle handler library
Copyright (C) 2001 NAKAMURA Hiroshi.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PRATICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 675 Mass
Ave, Cambridge, MA 02139, USA.
=end

require 'soap/encoding'
require 'soap/nqxmlDocument'


module SOAP
  class SOAPEncodingStyleHandlerDynamic < EncodingStyleHandler
    class SOAPTemporalObject
      attr_accessor :parent
      attr_accessor :position
      attr_accessor :id
      attr_accessor :root

      def initialize
	@parent = nil
	@position = nil
	@id = nil
	@root = nil
      end
    end

    class SOAPUnknown < SOAPTemporalObject
      attr_accessor :textBuf

      def initialize( handler, ns, entity, typeNamespace, typeName )
	super()
	@textBuf = ''
	@handler = handler
	@ns = ns
	@entity = entity
	@typeNamespace = typeNamespace
	@typeName = typeName
      end

      def toStruct
	o = SOAPStruct.decode( @ns, @entity, @typeNamespace, @typeName )
	o.id = @id
	o.root = @root
	o.parent = @parent
	o.position = @position
	@handler.decodeParent( @parent, o )
	o
      end

      def toString
	o = SOAPString.decode( @ns, @entity )
	o.id = @id
	o.root = @root
	o.parent = @parent
	o.position = @position
	@handler.decodeParent( @parent, o )
	o
      end

      def toNil
	o = SOAPNil.decode( @ns, @entity )
	o.id = @id
	o.root = @root
	o.parent = @parent
	o.position = @position
	@handler.decodeParent( @parent, o )
	o
      end
    end

    def initialize
      super( EncodingNamespace )
      @referencePool = []
      @idPool = []
    end

    def decodeTag( ns, entity, parent )
      isNil, type, arrayType, reference, id, root, offset, position = parseAttrs( ns, entity )
      o = nil
      if isNil
	o = SOAPNil.decode( ns, entity )

      elsif arrayType
	typeNamespace, typeNameString = ns.parse( arrayType )
	o = SOAPArray.decode( ns, entity, typeNamespace, typeNameString )
	if offset
	  o.offset = parseArrayPosition( offset )
	end
	# ToDo: xsi:type should be checked here...

      elsif reference
	o = SOAPReference.decode( ns, entity, reference )
	@referencePool << o

      else
	typeNamespace = typeNameString = nil
	if type
	  typeNamespace, typeNameString = ns.parse( type )
	elsif parent.node.is_a?( SOAPArray )
	  typeNamespace, typeNameString = parent.node.typeNamespace, parent.node.typeName
	else
	  # Since it's in dynamic(without any type) encoding process,
	  # assumes entity as its type itself.
	  #   <SOAP-ENC:Array ...> => type Array in SOAP-ENC.
	  #   <Country xmlns="foo"> => type Country in foo.
	  typeNamespace, typeNameString = ns.parse( entity.name )
	end

	if typeNamespace == XSD::Namespace
	  o = decodeTagAsXSD( ns, typeNameString, entity )
	  unless o
	    # Not supported...
	    raise FormatDecodeError.new( "Type xsd:#{ typeNameString } have not supported." )
	  end

	elsif typeNamespace == EncodingNamespace
	  o = decodeTagAsSOAPENC( ns, typeNameString, entity )
	  unless o
	    # Not supported...
	    raise FormatDecodeError.new( "Type SOAP-ENC:#{ typeNameString } have not supported." )
	  end

	else
	  # Unknown type... Struct or String
	  o = SOAPUnknown.new( self, ns, entity, typeNamespace, typeNameString )

	end
      end

      o.parent = parent
      o.id = id 
      o.root = root

      unless o.is_a?( SOAPTemporalObject )
	@idPool << o if o.id
	decodeParent( parent, o )
      end

      o
    end

    def decodeTagAsXSD( ns, typeNameString, entity )
      if typeNameString == XSD::AnyTypeLiteral
	SOAPUnknown.new( self, ns, entity, XSD::Namespace, typeNameString )
      elsif typeNameString == XSD::DecimalLiteral
    	SOAPDecimal.decode( ns, entity )
      elsif typeNameString == XSD::IntegerLiteral
    	SOAPInteger.decode( ns, entity )
      elsif typeNameString == XSD::LongLiteral
    	SOAPLong.decode( ns, entity )
      elsif typeNameString == XSD::IntLiteral
    	SOAPInt.decode( ns, entity )
      elsif typeNameString == XSD::FloatLiteral
    	SOAPFloat.decode( ns, entity )
      elsif typeNameString == XSD::BooleanLiteral
    	SOAPBoolean.decode( ns, entity )
      elsif typeNameString == XSD::StringLiteral
    	SOAPString.decode( ns, entity )
      elsif typeNameString == XSD::DateTimeLiteral
   	SOAPDateTime.decode( ns, entity )
      elsif typeNameString == XSD::Base64BinaryLiteral
    	SOAPBase64.decode( ns, entity )
      else
	nil
      end
    end

    def decodeTagAsSOAPENC( ns, typeNameString, entity )
      if typeNameString == XSD::DecimalLiteral
    	SOAPDecimal.decode( ns, entity )
      elsif typeNameString == XSD::IntegerLiteral
    	SOAPInteger.decode( ns, entity )
      elsif typeNameString == XSD::LongLiteral
    	SOAPLong.decode( ns, entity )
      elsif typeNameString == XSD::IntLiteral
    	SOAPInt.decode( ns, entity )
      elsif typeNameString == XSD::FloatLiteral
        SOAPFloat.decode( ns, entity )
      elsif typeNameString == XSD::BooleanLiteral
        SOAPBoolean.decode( ns, entity )
      elsif typeNameString == XSD::StringLiteral
        SOAPString.decode( ns, entity )
      elsif typeNameString == XSD::DateTimeLiteral
        SOAPDateTime.decode( ns, entity )
      elsif typeNameString == SOAP::Base64Literal
        SOAPBase64.decode( ns, entity )
      else
	nil
      end
    end

    def decodeTagEnd( ns, node )
      o = node.node
      if o.is_a?( SOAPUnknown )
	if /\A\s*\z/ =~ o.textBuf
	  o.toStruct
	else
	  newNode = o.toString
	  if newNode.id
	    @idPool << newNode
	  end
	  node.replaceNode( newNode )
	  node.node.set( o.textBuf )
	end
      end
    end

    def decodeText( ns, entity, parent )
      case parent.node
      when SOAPUnknown
	parent.node.textBuf << entity.text
      when XSDBase64Binary
        parent.node.setEncoded( entity.text )
      when SOAPBasetype
        parent.node.set( entity.text )
      else
	# Nothing to do...
      end
    end

    def decodePrologue
      @referencePool.clear
      @idPool.clear
    end

    def decodeEpilogue
      resolveId
    end

    def decodeParent( parent, node )
      case parent.node
      when SOAPUnknown
	newParent = parent.node.toStruct
	node.parent = newParent
	# ID entiry was delayed.
	if newParent.id
	  @idPool << newParent
	end
	parent.replaceNode( newParent )
	decodeParent( parent, node )

      when SOAPReference
	raise FormatDecodeError.new( "Reference node must not have a child." )

      when SOAPStruct
       	parent.node.add( node.name, node )

      when SOAPArray
	if node.position
	  parent.node[ *( parseArrayPosition( node.position )) ] = node
	else
	  parent.node.add( node )
	end

      when SOAPBasetype
	raise FormatDecodeError.new( "SOAP base type must not have a child." )

      else
	# SOAPUnknown does not have parent.
	# raise FormatDecodeError.new( "Illegal parent: #{ parent }." )
      end
    end

  private

    def parseAttrs( ns, entity )
      isNil = false
      type = nil
      arrayType = nil
      reference = nil
      id = nil
      root = nil
      offset = nil
      position = nil

      entity.attrs.each do | key, value |
	if ( ns.compare( XSD::Namespace, XSD::NilLiteral, key ))
	  isNil = ( value == XSD::NilValue )
	elsif ( ns.compare( XSD::InstanceNamespace, XSD::AttrType, key ))
	  type = value
	elsif ( ns.compare( EncodingNamespace, AttrArrayType, key ))
	  arrayType = value
	elsif ( key == 'href' )
	  reference = value
	elsif ( key == 'id' )
	  id = value
	elsif ( ns.compare( EncodingNamespace, AttrRoot, key ))
	  if value == '1'
	    root = 1
	  elsif value == '0'
	    root = 0
	  else
	    raise FormatDecodeError.new( "Illegal root attribute value: #{ value }." )
	  end
	elsif ( ns.compare( EncodingNamespace, AttrOffset, key ))
	  offset = value
	elsif ( ns.compare( EncodingNamespace, AttrPosition, key ))
	  position = value
	end
      end

      return isNil, type, arrayType, reference, id, root, offset, position
    end

    def parseArrayPosition( position )
      /^\[(.+)\]$/ =~ position
      $1.split( ',' ).collect { |s| s.to_i }
    end

    def resolveId
      count = @referencePool.length	# To avoid infinite loop
      while !@referencePool.empty? && count > 0
	@referencePool = @referencePool.find_all { | ref |
	  count -= 1
	  o = @idPool.find { | item |
	    ( '#' << item.id == ref.refId )
	  }
	  unless o
	    raise FormatDecodeError.new( "Unresolved reference: #{ ref.refId }." )
	  end
	  if o.is_a?( SOAPReference )
	    true
	  else
	    ref.__setobj__( o )
	    false
	  end
	}
      end
    end
  end

  SOAPEncodingStyleHandlerDynamic.new
end
