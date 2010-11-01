// TemplateExtracter.g
//
// Crawler that extracts the signatures (typereptemplates) from a CSharp AST 
//
// Kevin Glynn
// kevin.glynn@twigletsoftware.com
// June 2010
  
tree grammar TemplateExtracter;

options {
    tokenVocab=cs;
    ASTLabelType=CommonTree;
    language=CSharp2;
    superClass='RusticiSoftware.Translator.CSharp.CommonWalker';
    //output=AST;
    //backtrack=true;
}

// A scope to keep track of the namespaces available at any point in the program
scope NSContext {
   IList<UseRepTemplate> nss;
   string currentNS;
   TypeRepTemplate currentTypeRep;
}

@namespace { RusticiSoftware.Translator.CSharp }

@header
{
	using System.Text;
	using System.Linq;
	using RusticiSoftware.Translator.CLR;
	using RusticiSoftware.Translator.Utils;
}

@members 
{

    // This is the environment that we are building, it maps fully qualified type names to their
    // translation templates
    protected DirectoryHT<TypeRepTemplate> AppEnv {get; set;}

    protected UseRepTemplate[] NameSpaceContext {
        get {
            // We return the elements in source order (hopefully less confusing)
            // so when looking for types we search from last element to first.
            // here we are getting scopes in the opposite order so we need some
            // jiggery pokery to restore desired order.
             List<UseRepTemplate> rets = new List<UseRepTemplate>();
             // returns in LIFO order, like you would expect from a stack
             // sigh,  in C# we can't index into the scopes like you can in Java
             // so we resort to a bit of low level hackery to get the ns lists
             foreach (NSContext_scope nscontext in $NSContext) {
                 IList<UseRepTemplate> nss = nscontext.nss;
                 for (int i = nss.Count - 1; i >= 0; i--) {
                     rets.Add(nss[i]);
                 }
             }
             // And now return reversed list
			rets.Reverse();        
            return rets.ToArray();
        }
    }

    protected string ParentNameSpace {
        get {
            return ((NSContext_scope)$NSContext.ToArray()[$NSContext.Count-2]).currentNS;
        }
    }

    protected string formatTyargs(List<string> tyargs) {
               
        if (tyargs.Count == 0) {
            return "";
        }
        StringBuilder buf = new StringBuilder();
        buf.Append("<");
        foreach (string t in tyargs) {
            buf.Append(t + ",");
        }
        buf.Remove(buf.Length-1,1);
        buf.Append(">");
        return buf.ToString();
    }
}

/********************************************************************************************
                          Parser section
*********************************************************************************************/

///////////////////////////////////////////////////////

compilation_unit[CS2JSettings inCfg, DirectoryHT<TypeRepTemplate> inAppEnv]
scope NSContext;
@init{
    Cfg = inCfg;
    AppEnv = inAppEnv;
    // For initial, file level scope
    $NSContext::nss = new List<UseRepTemplate>();
    $NSContext::currentNS = "";
    $NSContext::currentTypeRep = null;
}
:
{ Debug("start template extraction"); }    
	namespace_body
{ Debug("end template extraction"); }    
	;

namespace_declaration
scope NSContext;
@init{
    $NSContext::nss = new List<UseRepTemplate>();
    $NSContext::currentTypeRep = null;
}
:
	'namespace'   qi=qualified_identifier  
        { Debug("namespace: " + $qi.text); 
          $NSContext::nss.Add(new UseRepTemplate($qi.text));
          // extend parent namespace
          $NSContext::currentNS = this.ParentNameSpace + $qi.text;
        }  
        namespace_block   ';'? ;
namespace_block:
	'{'   namespace_body   '}' ;
namespace_body:
	extern_alias_directives?   using_directives?   global_attributes?   namespace_member_declarations? ;
extern_alias_directives:
	extern_alias_directive+ ;
extern_alias_directive:
	e='extern'   'alias'   i=identifier  ';' { Warning($e.line, "[UNSUPPORTED] External Alias " + $i.text); } ;
using_directives:
	using_directive+ ;
using_directive:
	(using_alias_directive
	| using_namespace_directive) ;
using_alias_directive
@after{ $NSContext::nss.Add(new UseRepTemplate($i.text, $ns.text));}
    :
	'using'	  i=identifier   '='   ns=namespace_or_type_name   ';' ;
using_namespace_directive
@after{ $NSContext::nss.Add(new UseRepTemplate($ns.text));}
    :
	'using'   ns=namespace_name   ';' ;
namespace_member_declarations:
	namespace_member_declaration+ ;
namespace_member_declaration:
	namespace_declaration
	| attributes?   modifiers?   type_declaration ;
type_declaration:
	('partial') => p='partial'  { Warning($p.line, "[UNSUPPORTED] 'partial' definition"); } (class_declaration
								| struct_declaration
								| interface_declaration)
	| class_declaration
	| struct_declaration
	| interface_declaration
	| enum_declaration
	| delegate_declaration ;
	
	
// Identifiers
qualified_identifier:
	^(QID identifier+) ;
namespace_name
	: namespace_or_type_name ;

modifiers:
	modifier+ ;
modifier: 
	'new' | 'public' | 'protected' | 'private' | 'internal' | 'unsafe' | 'abstract' | 'sealed' | 'static'
	| 'readonly' | 'volatile' | 'extern' | 'virtual' | 'override';
	
class_member_declaration:
	attributes?
    // TODO:  Don't emit private
	m=modifiers?
	( 'const'   ct=type   constant_declarators[$ct.thetext]   ';'
	| event_declaration		// 'event'
	| p='partial' { Warning($p.line, "[UNSUPPORTED] 'partial' definition"); } (method_declaration["/* partial */"] 
			   | interface_declaration 
			   | class_declaration 
			   | struct_declaration)
	| interface_declaration	// 'interface'
	| 'void'   method_declaration["System.Void"]
	| rt=type ( (member_name   '(') => method_declaration[$rt.thetext]
		   | (member_name   '{') => property_declaration[$rt.thetext]
		   | (member_name   '.'   'this') => type_name '.' indexer_declaration[$rt.thetext, $type_name.thetext+"."]
		   | indexer_declaration[$rt.thetext, ""]	//this
	       | field_declaration[$rt.thetext]      // qid
	       | operator_declaration[$rt.thetext]
	       )
//	common_modifiers// (method_modifiers | field_modifiers)
	
	| class_declaration		// 'class'
	| struct_declaration	// 'struct'	   
	| enum_declaration		// 'enum'
	| delegate_declaration	// 'delegate'
	| conversion_operator_declaration
	| constructor_declaration	//	| static_constructor_declaration
	| destructor_declaration
	) 
	;

primary_expression: 
	('this'    brackets) => 'this'   brackets   primary_expression_part*
	| ('base'   brackets) => 'this'   brackets   primary_expression_part*
	| primary_expression_start   primary_expression_part*
	| 'new' (   (object_creation_expression   ('.'|'->'|'[')) => 
					object_creation_expression   primary_expression_part+ 		// new Foo(arg, arg).Member
				// try the simple one first, this has no argS and no expressions
				// symantically could be object creation
				| (delegate_creation_expression) => delegate_creation_expression// new FooDelegate (MyFunction)
				| object_creation_expression
				| anonymous_object_creation_expression)							// new {int X, string Y} 
	| sizeof_expression						// sizeof (struct)
	| checked_expression            		// checked (...
	| unchecked_expression          		// unchecked {...}
	| default_value_expression      		// default
	| anonymous_method_expression			// delegate (int foo) {}
	;

primary_expression_start:
	predefined_type            
	| (identifier    '<') => identifier   generic_argument_list
	| identifier ('::'   identifier)?
	| 'this' 
	| 'base'
	| paren_expression
	| typeof_expression             // typeof(Foo).Name
	| literal
	;

primary_expression_part:
	 access_identifier
	| brackets_or_arguments ;
access_identifier:
	access_operator   type_or_generic ;
access_operator:
	'.'  |  '->' ;
brackets_or_arguments:
	brackets | arguments ;
brackets:
	'['   expression_list?   ']' ;	
paren_expression:	
	'('   expression   ')' ;
arguments: 
	'('   argument_list?   ')' ;
argument_list: 
	argument (',' argument)*;
// 4.0
argument:
	argument_name   argument_value
	| argument_value;
argument_name:
	identifier   ':';
argument_value: 
	expression 
	| ref_variable_reference 
	| 'out'   variable_reference ;
ref_variable_reference:
	'ref' 
		(('('   type   ')') =>   '('   type   ')'   (ref_variable_reference | variable_reference)   // SomeFunc(ref (int) ref foo)
																									// SomeFunc(ref (int) foo)
		| variable_reference);	// SomeFunc(ref foo)
// lvalue
variable_reference:
	expression;
rank_specifiers: 
	rank_specifier+ ;        
rank_specifier: 
	'['   dim_separators?   ']' ;
dim_separators: 
	','+ ;

delegate_creation_expression: 
	// 'new'   
	type_name   '('   type_name   ')' ;
anonymous_object_creation_expression: 
	// 'new'
	anonymous_object_initializer ;
anonymous_object_initializer: 
	'{'   (member_declarator_list   ','?)?   '}';
member_declarator_list: 
	member_declarator  (',' member_declarator)* ; 
member_declarator: 
	qid   ('='   expression)? ;
primary_or_array_creation_expression:
	(array_creation_expression) => array_creation_expression
	| primary_expression 
	;
// new Type[2] { }
array_creation_expression:
	'new'   
		(type   ('['   expression_list   ']'   
					( rank_specifiers?   array_initializer?	// new int[4]
					// | invocation_part*
					| ( ((arguments   ('['|'.'|'->')) => arguments   invocation_part)// new object[2].GetEnumerator()
					  | invocation_part)*   arguments
					)							// new int[4]()
				| array_initializer		
				)
		| rank_specifier   // [,]
			(array_initializer	// var a = new[] { 1, 10, 100, 1000 }; // int[]
		    )
		) ;
array_initializer:
	'{'   variable_initializer_list?   ','?   '}' ;
variable_initializer_list:
	variable_initializer (',' variable_initializer)* ;
variable_initializer:
	expression	| array_initializer ;
sizeof_expression:
	'sizeof'   '('   unmanaged_type   ')';
checked_expression: 
	'checked'   '('   expression   ')' ;
unchecked_expression: 
	'unchecked'   '('   expression   ')' ;
default_value_expression: 
	'default'   '('   type   ')' ;
anonymous_method_expression:
	'delegate'   explicit_anonymous_function_signature?   block;
explicit_anonymous_function_signature:
	'('   explicit_anonymous_function_parameter_list?   ')' ;
explicit_anonymous_function_parameter_list:
	explicit_anonymous_function_parameter   (','   explicit_anonymous_function_parameter)* ;	
explicit_anonymous_function_parameter:
	anonymous_function_parameter_modifier?   type   identifier;
anonymous_function_parameter_modifier:
	'ref' | 'out';


///////////////////////////////////////////////////////
object_creation_expression: 
	// 'new'
	type   
		( '('   argument_list?   ')'   object_or_collection_initializer?  
		  | object_or_collection_initializer )
	;
object_or_collection_initializer: 
	'{'  (object_initializer 
		| collection_initializer) ;
collection_initializer: 
	element_initializer_list   ','?   '}' ;
element_initializer_list: 
	element_initializer  (',' element_initializer)* ;
element_initializer: 
	non_assignment_expression 
	| '{'   expression_list   '}' ;
// object-initializer eg's
//	Rectangle r = new Rectangle {
//		P1 = new Point { X = 0, Y = 1 },
//		P2 = new Point { X = 2, Y = 3 }
//	};
// TODO: comma should only follow a member_initializer_list
object_initializer: 
	member_initializer_list?   ','?   '}' ;
member_initializer_list: 
	member_initializer  (',' member_initializer) ;
member_initializer: 
	identifier   '='   initializer_value ;
initializer_value: 
	expression 
	| object_or_collection_initializer ;

///////////////////////////////////////////////////////

typeof_expression: 
	'typeof'   '('   ((unbound_type_name) => unbound_type_name
					  | type 
					  | 'void')   ')' ;
// unbound type examples
//foo<bar<X<>>>
//bar::foo<>
//foo1::foo2.foo3<,,>
unbound_type_name:		// qualified_identifier v2
//	unbound_type_name_start unbound_type_name_part* ;
	unbound_type_name_start   
		(((generic_dimension_specifier   '.') => generic_dimension_specifier   unbound_type_name_part)
		| unbound_type_name_part)*   
			generic_dimension_specifier
	;

unbound_type_name_start:
	identifier ('::' identifier)?;
unbound_type_name_part:
	'.'   identifier;
generic_dimension_specifier: 
	'<'   commas?   '>' ;
commas: 
	','+ ; 

///////////////////////////////////////////////////////
//	Type Section
///////////////////////////////////////////////////////

type_name returns [string thetext]: 
	namespace_or_type_name { $thetext = $namespace_or_type_name.thetext; };
namespace_or_type_name returns [string thetext]: 
	 t1=type_or_generic  { $thetext=t1.type+formatTyargs($t1.generic_arguments); } ('::' tc=type_or_generic { $thetext+="::"+tc.type+formatTyargs($tc.generic_arguments); })? ('.'   tn=type_or_generic { $thetext+="."+tn.type+formatTyargs($tn.generic_arguments); } )* ;
type_or_generic returns [string type, List<string> generic_arguments]
@init {
    $generic_arguments = new List<String>();
}
@after{
    $type = $t.text;
}:
	(identifier   '<') => t=identifier   ga=generic_argument_list { $generic_arguments = $ga.tyargs; }
	| t=identifier ;

// keving: as far as I can see this is (<interfacename>.)?identifier (<tyargs>)? at lease for C# 3.0 and less.
qid returns [string name, List<String> tyargs]:		// qualified_identifier v2
	qid_start   qid_part* { $name=$qid_start.name; $tyargs = $qid_start.tyargs; }
	;
qid_start returns [string name, List<String> tyargs]:
	predefined_type { $name = $predefined_type.thetext; }
	| (identifier    '<')	=> identifier   generic_argument_list { $name = $identifier.text; $tyargs = $generic_argument_list.tyargs; } 
//	| 'this'
//	| 'base'
	| i1=identifier  { $name = $i1.text; } ('::'   inext=identifier { $name+="::" + $inext.text; })?
	| literal { $name = $literal.text; }
	;		// 0.ToString() is legal


qid_part:
	access_identifier ;

generic_argument_list returns [List<string> tyargs]
@after { 
    $tyargs = $ta.tyargs;
}
: 
	'<'   ta=type_arguments   '>' ;
type_arguments returns [List<string> tyargs]
@init {
    $tyargs = new List<string>();
}
: 
	t1=type { $tyargs.Add($t1.thetext); } (',' tn=type { $tyargs.Add($tn.thetext); })* ;

type returns [string thetext]:
	  ((predefined_type | type_name)  rank_specifiers) => (p1=predefined_type { $thetext = $p1.thetext; } | tn1=type_name { $thetext = $tn1.thetext; })   rs=rank_specifiers  { $thetext += $rs.text; } ('*' { $thetext += "*"; })*
	| ((predefined_type | type_name)  ('*'+ | '?')) => (p2=predefined_type { $thetext = $p2.thetext; } | tn2=type_name { $thetext = $tn2.thetext; })   (('*' { $thetext += "*"; })+ | '?' { $thetext += "?"; })
	| (p3=predefined_type { $thetext = $p3.thetext; } | tn3=type_name { $thetext = $tn3.thetext; })
	| 'void' { $thetext = "System.Void"; } ('*' { $thetext += "*"; })+
	;
non_nullable_type:
	(predefined_type | type_name)
		(   rank_specifiers   '*'*
			| ('*'+)?
		)
	| 'void'   '*'+ ;
	
non_array_type:
	type;
array_type:
	type;
unmanaged_type:
	type;
class_type:
	type;
pointer_type:
	type;


///////////////////////////////////////////////////////
//	Statement Section
///////////////////////////////////////////////////////
block:
	';'
	| '{'   statement_list?   '}';
statement_list:
	statement+ ;
	
///////////////////////////////////////////////////////
//	Expression Section
///////////////////////////////////////////////////////	
expression: 
	(unary_expression   assignment_operator) => assignment	
	| non_assignment_expression
	;
expression_list:
	expression  (','   expression)* ;
assignment:
	unary_expression   assignment_operator   expression ;
unary_expression: 
	//('(' arguments ')' ('[' | '.' | '(')) => primary_or_array_creation_expression
	(cast_expression) => cast_expression
	| primary_or_array_creation_expression   '++'?   '--'?
	| '+'   unary_expression 
	| '-'   unary_expression 
	| '!'   unary_expression 
	| '~'   unary_expression 
	| pre_increment_expression 
	| pre_decrement_expression 
	| pointer_indirection_expression
	| addressof_expression 
	;
cast_expression:
	'('   type   ')'   unary_expression ;
assignment_operator:
	'=' | '+=' | '-=' | '*=' | '/=' | '%=' | '&=' | '|=' | '^=' | '<<=' | '>' '>=' ;
pre_increment_expression: 
	'++'   unary_expression ;
pre_decrement_expression: 
	'--'   unary_expression ;
pointer_indirection_expression:
	'*'   unary_expression ;
addressof_expression:
	'&'   unary_expression ;

non_assignment_expression:
	//'non ASSIGNment'
	(anonymous_function_signature   '=>')	=> lambda_expression
	| (query_expression) => query_expression 
	| conditional_expression
	;

///////////////////////////////////////////////////////
//	Conditional Expression Section
///////////////////////////////////////////////////////

multiplicative_expression:
	unary_expression (  ('*'|'/'|'%')   unary_expression)*	;
additive_expression:
	multiplicative_expression (('+'|'-')   multiplicative_expression)* ;
// >> check needed (no whitespace)
shift_expression:
	additive_expression (('<<'|'>' '>') additive_expression)* ;
relational_expression:
	shift_expression
		(	(('<'|'>'|'>='|'<=')	shift_expression)
			| (('is'|'as')   non_nullable_type)
		)* ;
equality_expression:
	relational_expression
	   (('=='|'!=')   relational_expression)* ;
and_expression:
	equality_expression ('&'   equality_expression)* ;
exclusive_or_expression:
	and_expression ('^'   and_expression)* ;
inclusive_or_expression:
	exclusive_or_expression   ('|'   exclusive_or_expression)* ;
conditional_and_expression:
	inclusive_or_expression   ('&&'   inclusive_or_expression)* ;
conditional_or_expression:
	conditional_and_expression  ('||'   conditional_and_expression)* ;

null_coalescing_expression:
	conditional_or_expression   ('??'   conditional_or_expression)* ;
conditional_expression:
	null_coalescing_expression   ('?'   expression   ':'   expression)? ;
      
///////////////////////////////////////////////////////
//	lambda Section
///////////////////////////////////////////////////////
lambda_expression:
	anonymous_function_signature   '=>'   anonymous_function_body;
anonymous_function_signature:
	'('	(explicit_anonymous_function_parameter_list
		| implicit_anonymous_function_parameter_list)?	')'
	| implicit_anonymous_function_parameter_list
	;
implicit_anonymous_function_parameter_list:
	implicit_anonymous_function_parameter   (','   implicit_anonymous_function_parameter)* ;
implicit_anonymous_function_parameter:
	identifier;
anonymous_function_body:
	expression
	| block ;

///////////////////////////////////////////////////////
//	LINQ Section
///////////////////////////////////////////////////////
query_expression:
	from_clause   query_body ;
query_body:
	// match 'into' to closest query_body
	query_body_clauses?   select_or_group_clause   (('into') => query_continuation)? ;
query_continuation:
	'into'   identifier   query_body;
query_body_clauses:
	query_body_clause+ ;
query_body_clause:
	from_clause
	| let_clause
	| where_clause
	| join_clause
	| orderby_clause;
from_clause:
	'from'   type?   identifier   'in'   expression ;
join_clause:
	'join'   type?   identifier   'in'   expression   'on'   expression   'equals'   expression ('into' identifier)? ;
let_clause:
	'let'   identifier   '='   expression;
orderby_clause:
	'orderby'   ordering_list ;
ordering_list:
	ordering   (','   ordering)* ;
ordering:
	expression    ordering_direction
	;
ordering_direction:
	'ascending'
	| 'descending' ;
select_or_group_clause:
	select_clause
	| group_clause ;
select_clause:
	'select'   expression ;
group_clause:
	'group'   expression   'by'   expression ;
where_clause:
	'where'   boolean_expression ;
boolean_expression:
	expression;

///////////////////////////////////////////////////////
// B.2.13 Attributes
///////////////////////////////////////////////////////
global_attributes: 
	global_attribute+ ;
global_attribute: 
	'['   global_attribute_target_specifier   attribute_list   ','?   ']' ;
global_attribute_target_specifier: 
	global_attribute_target   ':' ;
global_attribute_target: 
	'assembly' | 'module' ;
attributes: 
	attribute_sections ;
attribute_sections: 
	attribute_section+ ;
attribute_section: 
	'['   attribute_target_specifier?   attribute_list   ','?   ']' ;
attribute_target_specifier: 
	attribute_target   ':' ;
attribute_target: 
	'field' | 'event' | 'method' | 'param' | 'property' | 'return' | 'type' ;
attribute_list: 
	attribute (',' attribute)* ; 
attribute: 
	type_name   attribute_arguments? ;
// TODO:  allows a mix of named/positional arguments in any order
attribute_arguments: 
	'('   (')'										// empty
		   | (positional_argument   ((','   identifier   '=') => named_argument
		   							 |','	positional_argument)*
			  )	')'
			) ;
positional_argument_list: 
	positional_argument (',' positional_argument)* ;
positional_argument: 
	attribute_argument_expression ;
named_argument_list: 
	named_argument (',' named_argument)* ;
named_argument: 
	identifier   '='   attribute_argument_expression ;
attribute_argument_expression: 
	expression ;

///////////////////////////////////////////////////////
//	Class Section
///////////////////////////////////////////////////////

class_declaration
scope NSContext;
@init {
    $NSContext::nss = new List<UseRepTemplate>();
    ClassRepTemplate klass = new ClassRepTemplate();
}
:
	'class'  type_or_generic   
        { 
            Debug("Processing class: " + $type_or_generic.type);
            klass.Uses = this.NameSpaceContext;
            klass.TypeName = this.ParentNameSpace + "." + $type_or_generic.type;
            if ($type_or_generic.generic_arguments.Count > 0) {
                // distinguish classes with same name, but differing numbers of type arguments
                klass.TypeName+= "'" + $type_or_generic.generic_arguments.Count.ToString();
            }
            klass.TypeParams = $type_or_generic.generic_arguments.ToArray();
            // Nested types can see things in this space
            $NSContext::nss.Add(new UseRepTemplate(klass.TypeName));
            $NSContext::currentNS = klass.TypeName;
            $NSContext::currentTypeRep = klass;
            AppEnv[klass.TypeName] = klass;
        }
        (cb=class_base { klass.Inherits =  $cb.typeList.ToArray(); } )?   
        type_parameter_constraints_clauses? class_body  ';'? ;

class_base returns [List<string> typeList]
@after {
    $typeList = $i.typeList;
}
:
	// syntactically base class vs interface name is the same
	//':'   class_type (','   interface_type_list)? ;
	':'   i=interface_type_list ;
	
interface_type_list returns [List<string> typeList]
@init {
    $typeList = new List<string>();
}
:
	t1=type { typeList.Add($t1.text); } (','   tn=type { typeList.Add($tn.text); } )* ;

class_body:
	'{'   class_member_declarations?   '}' ;
class_member_declarations:
	class_member_declaration+ ;

///////////////////////////////////////////////////////
constant_declaration:
	'const'   type   constant_declarators[$type.thetext]   ';' ;
constant_declarators [string type]:
	constant_declarator[$type] (',' constant_declarator[$type])* ;
constant_declarator [string type]:
	identifier   { ((ClassRepTemplate)$NSContext::currentTypeRep).Fields.Add(new FieldRepTemplate($type, $identifier.text)); } ('='   constant_expression)? ;
constant_expression:
	expression;

///////////////////////////////////////////////////////
field_declaration [string type]:
	variable_declarators[$type, false]   ';'	;
variable_declarators [string type, bool isEvent]:
	variable_declarator[$type, $isEvent] (','   variable_declarator[$type, $isEvent])* ;
variable_declarator [string type, bool isEvent]:
	type_name 
       { FieldRepTemplate f = new FieldRepTemplate($type, $type_name.text);
         if (isEvent) {
             ((ClassRepTemplate)$NSContext::currentTypeRep).Events.Add(f);
         }
        else {
             ((ClassRepTemplate)$NSContext::currentTypeRep).Fields.Add(f);
        }; } ('='   variable_initializer)? ;		// eg. event EventHandler IInterface.VariableName = Foo;

///////////////////////////////////////////////////////
method_declaration [string returnType]:
	method_header[$returnType]   method_body ;
method_header [string returnType]:
	member_name  '('   fpl=formal_parameter_list?   ')'   
     {  ((InterfaceRepTemplate)$NSContext::currentTypeRep).Methods.Add(new MethodRepTemplate($returnType, $member_name.name, ($member_name.tyargs == null ? null : $member_name.tyargs.ToArray()), $fpl.paramlist)); }
    type_parameter_constraints_clauses? ;
method_body:
	block ;
member_name returns [string name, List<String> tyargs]:
	qid { $name = $qid.name; $tyargs = $qid.tyargs; } ;		// IInterface<int>.Method logic added.

///////////////////////////////////////////////////////
property_declaration[string type]:
	member_name   '{'   accessor_declarations   '}' 
           { PropRepTemplate propRep = new PropRepTemplate($type, $member_name.name);
            propRep.CanRead = $accessor_declarations.hasGetter;
            propRep.CanWrite = $accessor_declarations.hasSetter;
            ((InterfaceRepTemplate)$NSContext::currentTypeRep).Properties.Add(propRep); }
;
accessor_declarations returns [bool hasGetter, bool hasSetter]
@int {
    $hasSetter = false;
    $hasGetter = false;
}
:
	attributes?
		(get_accessor_declaration { $hasGetter = true; }  attributes?   (set_accessor_declaration { $hasSetter = true; })?
		| set_accessor_declaration  { $hasSetter = true; } attributes?   (get_accessor_declaration { $hasGetter = true; })?) ;
get_accessor_declaration:
	accessor_modifier?   'get'   accessor_body ;
set_accessor_declaration:
	accessor_modifier?   'set'   accessor_body ;
accessor_modifier:
	'public' | 'protected' | 'private' | 'internal' ;
accessor_body:
	block ;

///////////////////////////////////////////////////////
event_declaration:
	'event'   type
		((member_name   '{') => member_name '{' event_accessor_declarations '}' { ((ClassRepTemplate)$NSContext::currentTypeRep).Events.Add(new FieldRepTemplate($type.thetext, $member_name.name)); } 
		| variable_declarators[$type.thetext, true]   ';')	// typename=foo;
		;
event_modifiers:
	modifier+ ;
event_accessor_declarations:
	attributes?   ((add_accessor_declaration   attributes?   remove_accessor_declaration)
	              | (remove_accessor_declaration   attributes?   add_accessor_declaration)) ;
add_accessor_declaration:
	'add'   block ;
remove_accessor_declaration:
	'remove'   block ;

///////////////////////////////////////////////////////
//	enum declaration
///////////////////////////////////////////////////////
enum_declaration:
	'enum'   identifier   enum_base?   enum_body   ';'? ;
enum_base:
	':'   integral_type ;
enum_body:
	'{' (enum_member_declarations ','?)?   '}' ;
enum_member_declarations:
	enum_member_declaration (',' enum_member_declaration)* ;
enum_member_declaration:
	attributes?   identifier   ('='   expression)? ;
//enum_modifiers:
//	enum_modifier+ ;
//enum_modifier:
//	'new' | 'public' | 'protected' | 'internal' | 'private' ;
integral_type: 
	'sbyte' | 'byte' | 'short' | 'ushort' | 'int' | 'uint' | 'long' | 'ulong' | 'char' ;

// B.2.12 Delegates
delegate_declaration:
	'delegate'   return_type   identifier  variant_generic_parameter_list?   
		'('   formal_parameter_list?   ')'   type_parameter_constraints_clauses?   ';' ;
delegate_modifiers:
	modifier+ ;
// 4.0
variant_generic_parameter_list:
	'<'   variant_type_parameters   '>' ;
variant_type_parameters:
	variant_type_variable_name (',' variant_type_variable_name)* ;
variant_type_variable_name:
	attributes?   variance_annotation?   type_variable_name ;
variance_annotation:
	'in' | 'out' ;

type_parameter_constraints_clauses:
	type_parameter_constraints_clause   (','   type_parameter_constraints_clause)* ;
type_parameter_constraints_clause:
	'where'   type_variable_name   ':'   type_parameter_constraint_list ;
// class, Circle, new()
type_parameter_constraint_list:                                                   
    ('class' | 'struct')   (','   secondary_constraint_list)?   (','   constructor_constraint)?
	| secondary_constraint_list   (','   constructor_constraint)?
	| constructor_constraint ;
//primary_constraint:
//	class_type
//	| 'class'
//	| 'struct' ;
secondary_constraint_list:
	secondary_constraint (',' secondary_constraint)* ;
secondary_constraint:
	type_name ;	// | type_variable_name) ;
type_variable_name: 
	identifier ;
constructor_constraint:
	'new'   '('   ')' ;
return_type:
	type
	|  'void';
formal_parameter_list returns [List<ParamRepTemplate> paramlist]
@init {
    $paramlist = new List<ParamRepTemplate>();
}:
	p1=formal_parameter { $paramlist.Add($p1.param); } (',' pn=formal_parameter { $paramlist.Add($pn.param); })* ;
formal_parameter returns [ParamRepTemplate param]:
	attributes?   (fp=fixed_parameter { $param = $fp.param; } | pa=parameter_array { $param = $pa.param; }) 
	| a='__arglist' { Warning($a.line, "[UNSUPPORTED] __arglist"); } ;	// __arglist is undocumented, see google
fixed_parameters returns [List<ParamRepTemplate> paramlist]
@init {
    $paramlist = new List<ParamRepTemplate>();
}:
	p1=fixed_parameter  { $paramlist.Add($p1.param); } (','   pn=fixed_parameter { $paramlist.Add($pn.param); })* ;
// 4.0
fixed_parameter returns [ParamRepTemplate param]
@init {
    bool isByRef = false;
}
:
        (pm=parameter_modifier { isByRef = ($pm.text == "ref" || $pm.text == "out");  })?   t=type   i=identifier  { $param=new ParamRepTemplate($t.thetext, $i.text, isByRef); } default_argument? ;
// 4.0
default_argument:
	'=' expression;
parameter_modifier:
	'ref' | 'out' | 'this' ;
parameter_array returns [ParamRepTemplate param]:
	'params'   t=type   i=identifier { $param=new ParamRepTemplate($t.thetext + "[]", $i.text, false); } ;

///////////////////////////////////////////////////////
interface_declaration:
	'interface'   identifier   variant_generic_parameter_list? 
    	interface_base?   type_parameter_constraints_clauses?   interface_body   ';'? ;
interface_modifiers: 
	modifier+ ;
interface_base: 
   	':' interface_type_list ;
interface_body:
	'{'   interface_member_declarations?   '}' ;
interface_member_declarations:
	interface_member_declaration+ ;
interface_member_declaration:
	attributes?    modifiers?
		('void'   interface_method_declaration
		| interface_event_declaration
		| type   ( (member_name   '(') => interface_method_declaration
		         | (member_name   '{') => interface_property_declaration 
				 | interface_indexer_declaration)
		) 
		;
interface_property_declaration: 
	identifier   '{'   interface_accessor_declarations   '}' ;
interface_method_declaration:
	identifier   generic_argument_list?
	    '('   formal_parameter_list?   ')'   type_parameter_constraints_clauses?   ';' ;
interface_event_declaration: 
	//attributes?   'new'?   
	'event'   type   identifier   ';' ; 
interface_indexer_declaration: 
	// attributes?    'new'?    type   
	'this'   '['   formal_parameter_list   ']'   '{'   interface_accessor_declarations   '}' ;
interface_accessor_declarations:
	attributes?   
		(interface_get_accessor_declaration   attributes?   interface_set_accessor_declaration?
		| interface_set_accessor_declaration   attributes?   interface_get_accessor_declaration?) ;
interface_get_accessor_declaration:
	'get'   ';' ;		// no body / modifiers
interface_set_accessor_declaration:
	'set'   ';' ;		// no body / modifiers
method_modifiers:
	modifier+ ;
	
///////////////////////////////////////////////////////
struct_declaration:
	'struct'   type_or_generic   struct_interfaces?   type_parameter_constraints_clauses?   struct_body   ';'? ;
struct_modifiers:
	struct_modifier+ ;
struct_modifier:
	'new' | 'public' | 'protected' | 'internal' | 'private' | 'unsafe' ;
struct_interfaces:
	':'   interface_type_list;
struct_body:
	'{'   struct_member_declarations?   '}';
struct_member_declarations:
	struct_member_declaration+ ;
struct_member_declaration:
	attributes?   m=modifiers?
	( 'const'   ct=type   constant_declarators[$ct.thetext]   ';'
	| event_declaration		// 'event'
	| 'partial' (method_declaration["/* partial */"] 
			   | interface_declaration 
			   | class_declaration 
			   | struct_declaration)

	| interface_declaration	// 'interface'
	| class_declaration		// 'class'
	| 'void'   method_declaration["System.Void"]
	| rt=type ( (member_name   '(') => method_declaration[$rt.thetext]
		   | (member_name   '{') => property_declaration[$rt.thetext]
		   | (member_name   '.'   'this') => type_name '.' indexer_declaration[$rt.thetext, $type_name.thetext+"."]
		   | indexer_declaration[$rt.thetext, ""]	//this
	       | field_declaration[$rt.thetext]      // qid
	       | operator_declaration[$rt.thetext]
	       )
//	common_modifiers// (method_modifiers | field_modifiers)
	
	| struct_declaration	// 'struct'	   
	| enum_declaration		// 'enum'
	| delegate_declaration	// 'delegate'
	| conversion_operator_declaration
	| constructor_declaration	//	| static_constructor_declaration
	) 
	;


///////////////////////////////////////////////////////
indexer_declaration [string returnType, string prefix]:
	indexer_declarator[$returnType, $prefix]   '{'   accessor_declarations   '}' ;
indexer_declarator [string returnType, string prefix]:
	//(type_name '.')?   
	'this'   '['   fpl=formal_parameter_list   ']' 
         {  ((InterfaceRepTemplate)$NSContext::currentTypeRep).Indexers.Add(new MethodRepTemplate($returnType, $prefix+"this", null, $fpl.paramlist)); }
    ;
	
///////////////////////////////////////////////////////
operator_declaration [string returnType]:
	operator_declarator[$returnType]   operator_body ;
operator_declarator [string returnType]
@init {
    string opText = "";
    List<ParamRepTemplate> paramList = new List<ParamRepTemplate>();
    bool unaryOp = false;
}
@after {
    MethodRepTemplate meth = new MethodRepTemplate($returnType, opText, null, paramList); 
    if (unaryOp) {
        ((ClassRepTemplate)$NSContext::currentTypeRep).UnaryOps.Add(meth);
    }
    else {
        ((ClassRepTemplate)$NSContext::currentTypeRep).BinaryOps.Add(meth);
    } 
}:
	'operator'   
		(('+' { opText = "+"; } | '-' { opText = "-"; })   '('   t0=type   i0=identifier { paramList.Add(new ParamRepTemplate($t0.thetext, $i0.text)); } (binary_operator_declarator[paramList] | unary_operator_declarator { unaryOp = true; })
		| overloadable_unary_operator { opText = $overloadable_unary_operator.text; } '('   t1=type   i1=identifier { paramList.Add(new ParamRepTemplate($t1.thetext, $i1.text)); } unary_operator_declarator { unaryOp = true;  } 
		| overloadable_binary_operator { opText = $overloadable_binary_operator.text; } '(' t2=type   i2=identifier { paramList.Add(new ParamRepTemplate($t2.thetext, $i2.text)); } binary_operator_declarator[paramList] ) ;
unary_operator_declarator:
	   ')' ;
overloadable_unary_operator:
	/*'+' |  '-' | */ '!' |  '~' |  '++' |  '--' |  'true' |  'false' ;
binary_operator_declarator [List<ParamRepTemplate> paramList]:
	','   type   identifier   ')' { $paramList.Add(new ParamRepTemplate($type.thetext, $identifier.text)); } ;
// >> check needed
overloadable_binary_operator:
	/*'+' | '-' | */ '*' | '/' | '%' | '&' | '|' | '^' | '<<' | '>' '>' | '==' | '!=' | '>' | '<' | '>=' | '<=' ; 

conversion_operator_declaration:
	conversion_operator_declarator   operator_body ;
conversion_operator_declarator:
	(i='implicit' { Warning($i.line, "[UNSUPPORTED] implicit user defined casts,  an explicit cast is always required."); } | 'explicit')  'operator'   tt=type   '('   tf=type   identifier   ')' 
         {  ((ClassRepTemplate)$NSContext::currentTypeRep).Casts.Add(new CastRepTemplate($tf.thetext, $tt.thetext)); }
    ;
operator_body:
	block ;

///////////////////////////////////////////////////////
constructor_declaration:
	constructor_declarator   constructor_body ;
constructor_declarator:
	identifier   '('   fpl=formal_parameter_list?   ')'   constructor_initializer? 
         {  ((ClassRepTemplate)$NSContext::currentTypeRep).Constructors.Add(new ConstructorRepTemplate($fpl.paramlist)); }
;
constructor_initializer:
	':'   ('base' | 'this')   '('   argument_list?   ')' ;
constructor_body:
	block ;

///////////////////////////////////////////////////////
//static_constructor_declaration:
//	identifier   '('   ')'  static_constructor_body ;
//static_constructor_body:
//	block ;

///////////////////////////////////////////////////////
destructor_declaration:
	'~'  identifier   '('   ')'    destructor_body ;
destructor_body:
	block ;

///////////////////////////////////////////////////////
invocation_expression:
	invocation_start   (((arguments   ('['|'.'|'->')) => arguments   invocation_part)
						| invocation_part)*   arguments ;
invocation_start:
	predefined_type 
	| (identifier    '<')	=> identifier   generic_argument_list
	| 'this' 
	| 'base'
	| identifier   ('::'   identifier)?
	| typeof_expression             // typeof(Foo).Name
	;
invocation_part:
	 access_identifier
	| brackets ;

///////////////////////////////////////////////////////

statement:
	(declaration_statement) => declaration_statement
	| (identifier   ':') => labeled_statement
	| embedded_statement 
	;
embedded_statement:
	block
	| selection_statement	// if, switch
	| iteration_statement	// while, do, for, foreach
	| jump_statement		// break, continue, goto, return, throw
	| try_statement
	| checked_statement
	| unchecked_statement
	| lock_statement
	| using_statement 
	| yield_statement 
	| unsafe_statement
	| fixed_statement
	| expression_statement	// expression!
	;
fixed_statement:
	'fixed'   '('   pointer_type fixed_pointer_declarators   ')'   embedded_statement ;
fixed_pointer_declarators:
	fixed_pointer_declarator   (','   fixed_pointer_declarator)* ;
fixed_pointer_declarator:
	identifier   '='   fixed_pointer_initializer ;
fixed_pointer_initializer:
	//'&'   variable_reference   // unary_expression covers this
	expression;
unsafe_statement:
	'unsafe'   block;
labeled_statement:
	identifier   ':'   statement ;
declaration_statement:
	(local_variable_declaration 
	| local_constant_declaration) ';' ;
local_variable_declaration:
	local_variable_type   local_variable_declarators ;
local_variable_type:
	('var') => 'var'
	| ('dynamic') => 'dynamic'
	| type ;
local_variable_declarators:
	local_variable_declarator (',' local_variable_declarator)* ;
local_variable_declarator:
	identifier ('='   local_variable_initializer)? ; 
local_variable_initializer:
	expression
	| array_initializer 
	| stackalloc_initializer;
stackalloc_initializer:
	'stackalloc'   unmanaged_type   '['   expression   ']' ;
local_constant_declaration:
	'const'   type   constant_declarators[$type.thetext] ;
expression_statement:
	expression   ';' ;

// TODO: should be assignment, call, increment, decrement, and new object expressions
statement_expression:
	expression
	;
selection_statement:
	if_statement
	| switch_statement ;
if_statement:
	// else goes with closest if
	'if'   '('   boolean_expression   ')'   embedded_statement (('else') => else_statement)?
	;
else_statement:
	'else'   embedded_statement	;
switch_statement:
	'switch'   '('   expression   ')'   switch_block ;
switch_block:
	'{'   switch_sections?   '}' ;
switch_sections:
	switch_section+ ;
switch_section:
	switch_labels   statement_list ;
switch_labels:
	switch_label+ ;
switch_label:
	('case'   constant_expression   ':')
	| ('default'   ':') ;
iteration_statement:
	while_statement
	| do_statement
	| for_statement
	| foreach_statement ;
while_statement:
	'while'   '('   boolean_expression   ')'   embedded_statement ;
do_statement:
	'do'   embedded_statement   'while'   '('   boolean_expression   ')'   ';' ;
for_statement:
	'for'   '('   for_initializer?   ';'   for_condition?   ';'   for_iterator?   ')'   embedded_statement ;
for_initializer:
	(local_variable_declaration) => local_variable_declaration
	| statement_expression_list 
	;
for_condition:
	boolean_expression ;
for_iterator:
	statement_expression_list ;
statement_expression_list:
	statement_expression (',' statement_expression)* ;
foreach_statement:
	'foreach'   '('   local_variable_type   identifier   'in'   expression   ')'   embedded_statement ;
jump_statement:
	break_statement
	| continue_statement
	| goto_statement
	| return_statement
	| throw_statement ;
break_statement:
	'break'   ';' ;
continue_statement:
	'continue'   ';' ;
goto_statement:
	'goto'   ( identifier
			 | 'case'   constant_expression
			 | 'default')   ';' ;
return_statement:
	'return'   expression?   ';' ;
throw_statement:
	'throw'   expression?   ';' ;
try_statement:
      'try'   block   ( catch_clauses   finally_clause?
					  | finally_clause);
//TODO one or both
catch_clauses:
	'catch'   (specific_catch_clauses | general_catch_clause) ;
specific_catch_clauses:
	specific_catch_clause   ('catch'   (specific_catch_clause | general_catch_clause))*;
specific_catch_clause:
	'('   class_type   identifier?   ')'   block ;
general_catch_clause:
	block ;
finally_clause:
	'finally'   block ;
checked_statement:
	'checked'   block ;
unchecked_statement:
	'unchecked'   block ;
lock_statement:
	'lock'   '('  expression   ')'   embedded_statement ;
using_statement:
	'using'   '('    resource_acquisition   ')'    embedded_statement ;
resource_acquisition:
	(local_variable_declaration) => local_variable_declaration
	| expression ;
yield_statement:
	'yield'   ('return'   expression   ';'
	          | 'break'   ';') ;


///////////////////////////////////////////////////////
//	Lexar Section
///////////////////////////////////////////////////////

predefined_type returns [string thetext]:
	  'bool'    { $thetext = "System.Boolean"; } 
    | 'byte'    { $thetext = "System.Byte"; }    
    | 'char'    { $thetext = "System.Char"; } 
    | 'decimal' { $thetext = "System.Decimal"; } 
    | 'double'  { $thetext = "System.Double"; } 
    | 'float'   { $thetext = "System.Single"; } 
    | 'int'     { $thetext = "System.Int32"; }   
    | 'long'    { $thetext = "System.Int64"; } 
    | 'object'  { $thetext = "System.Object"; } 
    | 'sbyte'   { $thetext = "System.SByte"; } 
	| 'short'   { $thetext = "System.Int16"; } 
    | 'string'  { $thetext = "System.String"; } 
    | 'uint'    { $thetext = "System.UInt32"; } 
    | 'ulong'   { $thetext = "System.UInt64"; } 
    | 'ushort'  { $thetext = "System.UInt16"; } 
    ;

identifier:
 	IDENTIFIER | 'add' | 'alias' | 'assembly' | 'module' | 'field' | 'method' | 'param' | 'property' | 'type'
	| 'yield' | 'from' | 'into' | 'join' | 'on' | 'where' | 'orderby' | 'group' | 'by' | 'ascending' | 'descending' | 'equals' | 'select' | 'pragma' | 'let' | 'remove' | 'set' | 'var' | '__arglist' | 'dynamic'; 

keyword:
	'abstract' | 'as' | 'base' | 'bool' | 'break' | 'byte' | 'case' |  'catch' | 'char' | 'checked' | 'class' | 'const' | 'continue' | 'decimal' | 'default' | 'delegate' | 'do' |	'double' | 'else' |	 'enum'  | 'event' | 'explicit' | 'extern' | 'false' | 'finally' | 'fixed' | 'float' | 'for' | 'foreach' | 'goto' | 'if' | 'implicit' | 'in' | 'int' | 'interface' | 'internal' | 'is' | 'lock' | 'long' | 'namespace' | 'new' | 'null' | 'object' | 'operator' | 'out' | 'override' | 'params' | 'private' | 'protected' | 'public' | 'readonly' | 'ref' | 'return' | 'sbyte' | 'sealed' | 'short' | 'sizeof' | 'stackalloc' | 'static' | 'string' | 'struct' | 'switch' | 'this' | 'throw' | 'true' | 'try' | 'typeof' | 'uint' | 'ulong' | 'unchecked' | 'unsafe' | 'ushort' | 'using' |	 'virtual' | 'void' | 'volatile' ;

also_keyword:
	'add' | 'alias' | 'assembly' | 'module' | 'field' | 'event' | 'method' | 'param' | 'property' | 'type' 
	| 'yield' | 'from' | 'into' | 'join' | 'on' | 'where' | 'orderby' | 'group' | 'by' | 'ascending' | 'descending' 
	| 'equals' | 'select' | 'pragma' | 'let' | 'remove' | 'set' | 'var' | '__arglist' | 'dynamic';

literal:
	Real_literal
	| NUMBER
	| Hex_number
	| Character_literal
	| STRINGLITERAL
	| Verbatim_string_literal
	| TRUE
	| FALSE
	| NULL 
	;