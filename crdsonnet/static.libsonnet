{
  local this = self,

  nilvalue:: '',

  nestInParents(name, parents, object)::
    std.foldr(
      function(p, acc)
        if p == name
        then acc
        else p + '+: { ' + acc + ' }',
      parents,
      object
    ),

  functionName(name)::
    local underscores = std.set(std.findSubstr('_', name));
    local n = std.join('', [
      if std.setMember(i - 1, underscores)
      then std.asciiUpper(name[i])
      else name[i]
      for i in std.range(0, std.length(name) - 1)
      if !std.setMember(i, underscores)
    ]);
    'with' + std.asciiUpper(n[0]) + n[1:],

  withFunction(name, parents, object)::
    |||
      %s(value%s): { %s },
    ||| % [
      this.functionName(name),
      (if 'default' in object
       then '=%s' % (if std.isString(object.default)
                     then '"%s"' % object.default
                     else object.default)
       else ''),
      this.nestInParents(name, parents, name + ': value'),
    ],

  withConstant(name, parents, object)::
    |||
      %s(): { %s },
    ||| % [
      this.functionName(name),
      this.nestInParents(name, parents, name + ": '" + object.const + "'"),
    ],

  withBoolean(name, parents, object)::
    |||
      %s(value=%s): { %s },
    ||| % [
      this.functionName(name),
      (if 'default' in object
       then object.default
       else 'true'),
      this.nestInParents(name, parents, name + ': value'),
    ],

  mixinFunction(name, parents, object)::
    |||
      %sMixin(value): { %s },
    ||| % [
      this.functionName(name),
      this.nestInParents(name, parents, name + '+: value'),
    ],

  arrayFunctions(name, parents, object)::
    |||
      %s(value): { %s },
      %sMixin(value): { %s },
    ||| % [
      this.functionName(name),
      this.nestInParents(
        name,
        parents,
        ' %s: if std.isArray(value) then value else [value] ' % name,
      ),
      this.functionName(name),
      this.nestInParents(
        name,
        parents,
        ' %s+: if std.isArray(value) then value else [value] ' % name,
      ),
    ],

  otherFunction(name, functionname, object)::
    '%s+: { %s(value): value },' % [
      name,
      functionname,
    ],

  named(name, object)::
    |||
      %s+: %s,
    ||| % [
      name,
      object,
    ],

  // Don't process refs in composite
  compositeRef(name, refname, parsed):: '',
  //|||
  //  ['%s']+: { ['%s']+: { %s } },
  //||| % [
  //  name,
  //  refname,
  //  parsed,
  //],

  properties(object)::
    '{ %s }' % object,

  withMixin(name, parents)::
    this.nestInParents(
      name,
      parents,
      '{ mixin: self }'
    ),

  newFunction(parents)::
    '{\n %s \n}' %
    this.nestInParents(
      'new',
      parents,
      |||
        new(name):
          self.withApiVersion()
          + self.withKind()
          + self.metadata.withName(name),
      |||,
    ),

  fromSchema(grouping, version, parsed)::
    '{\n %s \n}' %
    this.nestInParents(
      '',
      [grouping, version],
      parsed,
    ),
}
