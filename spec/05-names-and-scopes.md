# 5. Names and scopes


## 5.1 Scope

This chapter defines how declarations bind names and where those bindings are visible. Chapter 3 defines identifier formation and identity. Chapter 4 supplies one ordered compilation unit and the placement of top-level declarations and routine bodies. Chapters 6 through 8 define types, storage, values, lifetime, and declaration forms.

A scope controls where source text may refer to a declaration. It does not determine storage allocation, initialization, storage duration, or value lifetime; Chapter 7 defines those subjects.

Basie has no implicit declarations, overloads, generic parameters, nested routines, or qualified module names. A `private` top-level declaration is visible only within its own source part (Section 5.11). Formal parameters and named local variables use the declarations defined by Chapters 8 and 13.

## 5.2 Name identity

Chapter 3 establishes an identifier's exact preserved spelling as its identity. All name binding, collision detection, forward completion, and lookup use that complete case-sensitive identity. Letter case distinguishes names.

An implementation may use a hash or an interned ordinal to locate a candidate binding, but it must confirm equality from the complete preserved spelling. It must not fold case, compare only a prefix, truncate a spelling, or treat an unchecked hash match as equality.

## 5.3 Scope structure

Basie uses these scopes:

| Scope        | Bindings | Enclosing scope |
| ------------ | -------- | --------------- |
| Program      | Predefined names, and the named constants, record types, pools, top-level variables and routine signatures not marked `private` | None |
| Part         | The `private` top-level declarations of one source part | Program scope |
| Routine      | The routine's formal parameters, and the locals declared directly in its body | The part scope of the part holding the routine's body, as visible at the routine's position |
| Block        | The locals and local constants declared directly in one block | The innermost enclosing block or routine scope |
| Record field | The fields declared by one record type | None for ordinary-name lookup; selection uses the field scope associated with the record type |

One compilation has one program scope, and each source part one part scope. A part boundary opens no other scope, and a later part does not see an earlier part's `private` bindings.

A **block** is a statement sequence that the grammar delimits (design decision D28): each arm of an `if`, `elseif` or `else`; each `case` and `else` arm of a `select` (Chapter 11); each loop body (Chapter 12); and each `handle` body (Chapter 14, Section 14.6). The name in a `select` arm's `some(NAME)` is declared in that arm's block, at its start. A routine body is the outermost block of its routine and is the routine scope itself. A block scope begins where the block's statements begin and ends at the keyword that ends the block or starts the next arm.

A local variable or local constant may be declared at any statement position (Chapter 10). Its scope runs from its declaration point (Section 5.5) to the end of the innermost enclosing block. When control leaves that block, by reaching its end or by `exit`, `continue`, `return` or `fail`, the local's lifetime ends, and an owning local is freed (Chapter 7).

Each record type has its own field scope. A field scope is separate from the ordinary scopes and from every other record's field scope.

## 5.4 One ordinary namespace

Program, part, routine and block scopes use one ordinary namespace. A record type, pool, named constant, variable, routine, parameter or local with a given exact identity prevents another visible ordinary binding from using that identity. Type and value names do not occupy separate namespaces.

Name lookup first finds the one ordinary binding and then checks whether its declaration class is valid in context. A record type used as an expression, a variable used as a type, or a result-free routine used as a value is invalid. A pool name is valid both as a type, meaning an owning handle into that pool, and where Chapter 7 admits a pool as an operand, as in `new nodes(...)`. The compiler must not continue searching for another declaration of a more convenient class.

Basie has no overload sets. Two routines with the same identity conflict even when their parameter or result types differ. Enumeration and subrange types are absent and introduce no member or range namespaces.

Every ordinary binding has one canonical declaration. An abbreviated routine body completes an earlier forward declaration under Section 5.8; it is the only case in which a later header with the same identity is not a duplicate declaration.

For example, the single namespace accepts this pair of names:

```basie
record Point
    x as u16
end

var origin as Point
```

Case variants are distinct names, so this declaration is valid:

```basie
record Point
    x as u16
end

var point as Point
```

Repeating the exact type name in the same namespace is invalid:

```basie
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
| Pool                                 | After the complete pool declaration has been checked; a forward pool declaration (D40) makes the pool name visible as a type, before its record type and capacity are given |
| Routine definition without a forward | After the complete signature has been checked and before the body begins                                                                          |
| Forward routine declaration          | After the complete signature has been checked                                                                                                     |
| Formal parameters                    | Together, after an ordinary header is checked or an abbreviated body header opens its forward; visible throughout that body |
| Local variable or local constant     | After its complete declaration, including any initializer, has been checked; visible in the rest of its block, including nested blocks            |
| Record field                         | After the complete record declaration has been checked; visible only through selection on that record type                                        |

A declaration is not visible in its own type, bound, initializer, or other declaration operand. A record type is not visible in its own field list. These rules reject self-reference by non-routine declarations and prevent declaration cycles without a dependency graph or a second declaration pass.

```basie
const first = second   // invalid: second is not yet visible
const second = 2

const count = count    // invalid: count is not visible in its initializer
```

Declaration order applies across the whole logical compilation unit. A later declaration does not become visible to an earlier routine merely because an implementation retained the source or built a syntax tree.

## 5.6 Duplicate declarations and shadowing

Two declarations in the same scope conflict when their exact case-sensitive identities are equal. A difference in letter case creates a different name; repeating the same spelling is a duplicate.

Lookup never selects a later declaration in preference to an earlier one. Basie has no temporal shadowing, source-level replacement, or latest-definition rule.

A parameter or local must not shadow any ordinary binding visible at its declaration point: a program binding, a part binding, a parameter, or a local of an enclosing block. Basie has no shadowing at any level. Locals in blocks that do not enclose one another may use the same identity, because neither is visible where the other is declared:

```basie
sub show(flag as boolean)
    if flag
        var count as u8 = 1
        ...
    else
        var count as u16 = 2     // valid: the first count is out of scope
        ...
    end
end
```

```basie
const limit = 10

sub clamp(limit as u16)       // invalid: parameter shadows visible constant
    return
end
```

The no-shadowing rule is evaluated at the declaration point. A program declaration that appears after an earlier routine is not visible in that routine and does not retroactively invalidate one of its parameter or local names.

Within one record, two fields with the same exact identity conflict. The same field identity may appear in different records, and a field may share an identity with an ordinary binding, because field selection supplies the record type before field lookup.

```basie
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
| A name after `.`                       | Use the selected record's field scope, or require intrinsic `length` when the base is a bounded string, or `length` or `capacity` when it is a `string[]` parameter |
| `id` before a pool name in a type, or `id(` in an expression | The contextual word of Chapter 3 (design decision D29); otherwise `id` is an ordinary name |
| An ordinary name inside a routine      | Search the visible locals of the enclosing blocks from the innermost outwards, then the parameters, then the routine's part scope, then the program scope |
| An ordinary name at top level          | Search the visible part scope, then the program scope                                                   |

The no-shadowing rule ensures that no two of these searches can produce valid bindings for the same identity, so the search order affects only speed, never the result. Field names are never found by unqualified ordinary lookup.

If lookup finds no binding, the compiler must issue an undeclared-name diagnostic. It must not create a variable, infer a declaration class, or grant visibility to a later declaration. If lookup finds a binding of the wrong class for the context, the compiler must diagnose that class mismatch.

## 5.8 Forward routine signatures

An explicit forward signature, and a forward pool declaration (D40), are the only source forms that create a name binding before its definition. After its complete signature has been checked, it creates the routine's canonical program-scope binding and retains the parameter names and ordered types, optional result type, and `fails` effect. The parameter names do not become program-scope bindings or open a routine scope at the forward declaration.

The later abbreviated body header, `sub NAME`, completes that binding. It does not declare a second routine or repeat any signature component. The name must resolve by exact identity to one incomplete forward. At that point, the forward's parameter names become the formal bindings in the routine scope and remain the only parameter spellings for the body.

A routine may have at most one forward declaration and one definition. A second forward declaration, a forward declaration after a definition, an abbreviated body without one matching incomplete forward, or another completion is invalid. Every forward declaration must have a completing definition in the same compilation unit.

Forward declarations apply only to routines and pools. Constants, variables, record types, fields, parameters, and locals have no forward form.

This completion matches:

```basie
forward sub emit(value as u8)

sub emit
    return
end
```

## 5.9 Self-reference and recursive call graphs

After a routine's complete signature has been checked, its binding is visible in its own body. A **call** to a routine whose body is not yet complete, which includes a call from a routine to itself, is valid only when the routine has a forward declaration (Chapter 4, Section 4.5). Without one, the call is diagnosed as `recursion-needs-forward`. The rule makes every cycle of calls pass through a forward-declared routine, which carries the activation-capacity check ([memory safety](../docs/memory-safety.md), Section 7; Chapter 13).

Mutual references require forward signatures for every later routine that an earlier body names. In this example both calls are valid: `second` through its forward declaration, and `first` because its body is complete before `second`'s begins:

```basie
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

A routine calling itself needs the same form:

```basie
forward sub countDown(n as u8)

sub countDown
    if n > 0
        countDown(n - 1)
    end
end
```

## 5.10 Reserved, predefined, entry, and generated names

Reserved words, built-in type words, and Boolean literals recognized by Chapter 3 are tokens rather than ordinary bindings. A source declaration cannot use their spellings as identifiers.

Chapter 16 defines the complete standard set of predefined source routines and constants. The compiler establishes those ordinary program-scope bindings before the first source token. User declarations and routine-scope declarations cannot redeclare or shadow them. An implementation extension may add names only under the explicit extension rules in Section 1.7.

`main` is not a predefined binding. Its required lowercase source definition creates the ordinary routine binding and must satisfy Section 4.7. `main` cannot be `private`. A differently cased name such as `Main` is distinct and does not satisfy the entry rule. No other program-scope or part-scope declaration may use the exact identity `main`; a field, a parameter or a local may, since it is not in the scope where `main` is declared.

Compiler-generated temporaries, labels, and helper names remain outside the source namespace. They cannot collide with a source identifier or become visible to source lookup.

## 5.11 Private declarations

The word `private` before a top-level declaration places its binding in the part scope of its source part instead of the program scope (design decision D33):

```basie
private const bufferSize = 64
private sub flushBuffer()
    ...
end
```

1. A `private` binding is visible only within its own part, from its declaration point on, under the ordinary rules of Section 5.5.
2. A `private` declaration must not use the identity of any binding visible at its declaration point, as for any declaration.
3. A later part may declare a binding with the same identity as an earlier part's `private` binding, since that binding is not visible there. So two parts of the standard library may each have a private `helper`.
4. A `private` forward routine declaration must be completed in the same part. A forward declaration that is not `private` may be completed in a later part; its completion repeats the forward's visibility, `private` exactly when the forward is, and a mismatch is `forward-mismatch`.
5. Record fields, parameters and locals cannot be marked `private`; they are already local to their scope.

`private` affects visibility only. A private routine, constant, pool or variable is compiled, linked and freed exactly like a public one, and its name appears in the name stream for reports and the symbol file.

## 5.12 Diagnostics and capacity limits

The compiler must diagnose an undeclared use, an exact duplicate, forbidden shadowing, a wrong declaration class, a call needing a forward declaration, an abbreviated body without one incomplete forward, a second completion, an uncompleted forward declaration, and a `private` forward completed in another part. It may stop after the first diagnostic under Chapter 1, Section 1.9.

An implementation may bound identifier length, retained name bytes, ordinary bindings, routine-local bindings, record fields, or unresolved forward signatures. It must document each limit and issue a capacity diagnostic before truncation, wraparound, dropped declarations, or unchecked collision can occur. A capacity failure does not change identifier identity or make an otherwise conforming program invalid.

The implementation may use one bounded ordinary symbol table, a mark for the current part's private names, a stack of marks for the current routine and its open blocks, and a field table associated with each record type. That layout is non-normative. The observable lookup, collision, visibility, and diagnostic rules above remain the same for any internal representation.
