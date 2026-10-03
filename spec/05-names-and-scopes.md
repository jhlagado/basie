# 5. Names and scopes


## 5.1 Scope

This chapter defines how declarations bind names and where those bindings are visible. Chapter 3 defines identifier formation and identity. Chapter 4 supplies one ordered compilation unit and the placement of top-level declarations and routine bodies. Chapters 6 through 8 define types, storage, values, lifetime, and declaration forms.

A scope controls where source text may refer to a declaration. It does not determine storage allocation, initialization, storage duration, or value lifetime; Chapter 7 defines those subjects.

Baton has no implicit declarations, overloads, generic parameters, nested routines, or source-level module namespaces. Formal parameters and named local variables use the declarations defined by Chapters 8 and 13.

## 5.2 Name identity

Chapter 3 establishes an identifier's exact preserved spelling as its identity. All name binding, collision detection, forward completion, and lookup use that complete case-sensitive identity. Letter case distinguishes names.

An implementation may use a hash or an interned ordinal to locate a candidate binding, but it must confirm equality from the complete preserved spelling. It must not fold case, compare only a prefix, truncate a spelling, or treat an unchecked hash match as equality.

## 5.3 Scope structure

Baton uses these scopes:

| Scope        | Bindings                                                                                     | Enclosing scope                                                                               |
| ------------ | -------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Program      | Predefined names, named constants, record types, top-level variables, and routine signatures | None                                                                                          |
| Routine      | The routine's formal parameters and named local variables                                    | Program scope as visible at the routine's source position                                     |
| Record field | The fields declared by one record type                                                       | None for ordinary-name lookup; selection uses the field scope associated with the record type |

One compilation unit has one program scope. A source-part boundary does not open another scope. Chapter 4 defines how ordered source parts contribute to that unit.

Each routine definition has one routine scope. Parameters and locals are binding classes within that scope, not separate nested scopes. Conditional clauses, loops, and other statement blocks do not open name scopes. Local declarations therefore remain in the routine's declaration prefix and cannot appear inside a statement block.

Each record type has its own field scope. A field scope is separate from the ordinary scopes and from every other record's field scope.

## 5.4 One ordinary namespace

Program and routine scopes use one ordinary namespace. A record type, named constant, variable, routine, parameter, or local with a given exact identity prevents another visible ordinary binding from using that identity. Type and value names do not occupy separate namespaces.

Name lookup first finds the one ordinary binding and then checks whether its declaration class is valid in context. A record type used as an expression, a variable used as a type, or a result-free routine used as a value is invalid. The compiler must not continue searching for another declaration of a more convenient class.

Baton has no overload sets. Two routines with the same identity conflict even when their parameter or result types differ. Enumeration and subrange types are absent and introduce no member or range namespaces.

Every ordinary binding has one canonical declaration. An abbreviated routine body completes an earlier forward declaration under Section 5.8; it is the only case in which a later header with the same identity is not a duplicate declaration.

For example, the single namespace accepts this pair of names:

```nucleus
record Point
    x as u16
end

var origin as Point
```

Case variants are distinct names, so this declaration is valid:

```nucleus
record Point
    x as u16
end

var point as Point
```

Repeating the exact type name in the same namespace is invalid:

```nucleus
record Point
    x as u16
end

var Point as Point       // invalid: exact duplicate of the type name
```

## 5.5 Declaration visibility

A completed declaration must precede every use. For routines, the checked signature is the declaration: an ordinary header exposes its name before its own body, and a forward header exposes the name before the later definition.

| Declaration                          | Declaration point and later visibility                                                                                                            |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Predefined name                      | Before the first source token; visible throughout the unit                                                                                        |
| Named constant or program variable   | After the complete declaration, including its type and any initializer, has been checked                                                          |
| Record type                          | After the complete record declaration, including every field, has been checked                                                                    |
| Routine definition without a forward | After the complete signature has been checked and before the body begins                                                                          |
| Forward routine declaration          | After the complete signature has been checked                                                                                                     |
| Formal parameters                    | Together, after an ordinary header is checked or an abbreviated body header opens its forward; visible in that body's local prefix and statements |
| Local variable                       | After its complete declaration, including any initializer, has been checked; visible in later local declarations and the body                     |
| Record field                         | After the complete record declaration has been checked; visible only through selection on that record type                                        |

A declaration is not visible in its own type, bound, initializer, or other declaration operand. A record type is not visible in its own field list. These rules reject self-reference by non-routine declarations and prevent declaration cycles without a dependency graph or a second declaration pass.

```nucleus
const first = second   // invalid: second is not yet visible
const second = 2

const count = count    // invalid: count is not visible in its initializer
```

Declaration order applies across the whole logical compilation unit. A later declaration does not become visible to an earlier routine merely because an implementation retained the source or built a syntax tree.

## 5.6 Duplicate declarations and shadowing

Two declarations in the same scope conflict when their exact case-sensitive identities are equal. A difference in letter case creates a different name; repeating the same spelling is a duplicate.

Lookup never selects a later declaration in preference to an earlier one. Baton has no temporal shadowing, source-level replacement, or latest-definition rule.

A parameter or local must not shadow an ordinary program binding visible at its declaration point. A local must not reuse the identity of a parameter or an earlier local. Because routine bodies contain no nested declaration scopes, no inner-block shadowing case exists.

```nucleus
const limit = 10

sub clamp(limit as u16)       // invalid: parameter shadows visible constant
    return
end
```

The no-shadowing rule is evaluated at the declaration point. A program declaration that appears after an earlier routine is not visible in that routine and does not retroactively invalidate one of its parameter or local names.

Within one record, two fields with the same exact identity conflict. The same field identity may appear in different records, and a field may share an identity with an ordinary binding, because field selection supplies the record type before field lookup.

```nucleus
record Point
    value as u16
end

record Sample
    value as u8            // valid: a different field scope
end

const value = 0     // valid: the ordinary namespace
```

## 5.7 Lookup

The compiler resolves a name at its source position in this order:

| Context                                | Lookup                                                                                                 |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| A reserved word or built-in type token | Use the token established by Chapter 3; perform no ordinary-name lookup                                |
| A name after `.`                       | Use the selected record's field scope, or require intrinsic `length` when the base is a bounded string |
| An ordinary name inside a routine      | Search visible parameters and locals in the current routine scope, then the visible program scope      |
| An ordinary name at top level          | Search the visible program scope                                                                       |

The no-shadowing rule ensures that the routine and program searches cannot both produce valid bindings for the same identity. Field names are never found by unqualified ordinary lookup.

If lookup finds no binding, the compiler must issue an undeclared-name diagnostic. It must not create a variable, infer a declaration class, or grant visibility to a later declaration. If lookup finds a binding of the wrong class for the context, the compiler must diagnose that class mismatch.

## 5.8 Forward routine signatures

An explicit forward signature is the only source form that creates a name binding before its body. After its complete signature has been checked, it creates the routine's canonical program-scope binding and retains the parameter names and ordered types, optional result type, and `fails` effect. The parameter names do not become program-scope bindings or open a routine scope at the forward declaration.

The later abbreviated body header, `sub NAME`, completes that binding. It does not declare a second routine or repeat any signature component. The name must resolve by exact identity to one incomplete forward. At that point, the forward's parameter names become the formal bindings in the routine scope and remain the only parameter spellings for the body.

A routine may have at most one forward declaration and one definition. A second forward declaration, a forward declaration after a definition, an abbreviated body without one matching incomplete forward, or another completion is invalid. Every forward declaration must have a completing definition in the same compilation unit.

Forward declarations apply only to source routines. Constants, variables, record types, fields, parameters, and locals have no forward form.

This completion matches:

```nucleus
forward sub emit(value as u8)

sub emit
    return
end
```

## 5.9 Self-reference and recursive call graphs

After a routine's complete signature has been checked, its program-scope binding is visible in its own body. Name resolution therefore permits a direct self-reference without a forward declaration.

Mutual references require forward signatures for every later routine that an earlier body names. In this example, `second` is visible through its forward declaration, while `first` is visible after its own header:

```nucleus
forward sub second(value as u16)

sub first(value as u16)
    second(value)
    return
end

sub second
    first(value)
    return
end
```

Under these rules, those names resolve. Chapter 13 admits recursive calls and defines their call semantics; Chapter 7 defines activation storage and lifetime. Implementation staging must not change the name-resolution result.

## 5.10 Reserved, predefined, entry, and generated names

Reserved words, built-in type words, and Boolean literals recognized by Chapter 3 are tokens rather than ordinary bindings. A source declaration cannot use their spellings as identifiers.

Chapter 16 defines the complete standard set of predefined source routines and constants. The compiler establishes those ordinary program-scope bindings before the first source token. User declarations and routine-scope declarations cannot redeclare or shadow them. An implementation extension may add names only under the explicit extension rules in Section 1.7.

`main` is not a predefined binding. Its required lowercase source definition creates the ordinary routine binding and must satisfy Section 4.7. A differently cased name such as `Main` is distinct and does not satisfy the entry rule. No other declaration may use the exact identity `main`.

Compiler-generated temporaries, labels, and helper names remain outside the source namespace. They cannot collide with a source identifier or become visible to source lookup.

## 5.11 Diagnostics and capacity limits

The compiler must diagnose an undeclared use, an exact duplicate, forbidden shadowing, a wrong declaration class, an abbreviated body without one incomplete forward, a second completion, and an uncompleted forward declaration. It may stop after the first diagnostic under Chapter 1.

An implementation may bound identifier length, retained name bytes, ordinary bindings, routine-local bindings, record fields, or unresolved forward signatures. It must document each limit and issue a capacity diagnostic before truncation, wraparound, dropped declarations, or unchecked collision can occur. A capacity failure does not change identifier identity or make an otherwise conforming program invalid.

The implementation may use one bounded ordinary symbol table, a mark for the current routine, and a field table associated with each record type. That layout is non-normative. The observable lookup, collision, visibility, and diagnostic rules above remain the same for any internal representation.
