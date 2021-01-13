[#ftl strict_vars=true]
[#--
/* Copyright (c) 2008-2020 Jonathan Revusky, revusky@javacc.com
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *     * Redistributions of source code must retain the above copyright notices,
 *       this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name Jonathan Revusky, Sun Microsystems, Inc.
 *       nor the names of any contributors may be used to endorse 
 *       or promote products derived from this software without specific prior written 
 *       permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */
 --]

[#-- This template contains the core logic for generating the various parser routines. --]

[#import "CommonUtils.java.ftl" as CU]

[#var nodeNumbering = 0]
[#var NODE_USES_PARSER = grammar.nodeUsesParser]
[#var NODE_PREFIX = grammar.nodePrefix]
[#var currentProduction]

[#macro Productions] 
 //=================================
 // Start of methods for BNF Productions
 //This code is generated by the ParserProductions.java.ftl template. 
 //=================================
  [#list grammar.parserProductions as production]
    [#set currentProduction = production]
    [@ParserProduction production/]
  [/#list]
[/#macro]

[#macro ParserProduction production]
    [@CU.firstSetVar production.expansion/]
    ${production.leadingComments}
// ${production.location}
    final ${production.accessMod!"public"} 
    ${production.returnType}
    ${production.name}(${production.parameterList!}) 
    throws ParseException
    [#list (production.throwsList.types)! as throw], ${throw}[/#list] {
     if (trace_enabled) LOGGER.info("Entering production defined on line ${production.beginLine} of ${production.inputSource?j_string}");
     if (cancelled) throw new CancellationException();
     String prevProduction = currentlyParsedProduction;
     this.currentlyParsedProduction = "${production.name}";
   [@BuildCode production.expansion /]
    }   
[/#macro]

[#-- The next 100 lines are too messy and need a significant cleanup --]
[#macro BuildCode expansion]
   [#if expansion.simpleName != "ExpansionSequence"]
  // Code for ${expansion.simpleName} specified at:
  // ${expansion.location}
  [/#if]
    [#var nodeVarName, parseExceptionVar, production, treeNodeBehavior, buildTreeNode=false, closeCondition = "true", callStackSizeVar]
    [#set treeNodeBehavior = expansion.treeNodeBehavior]
    [#if expansion.parent.simpleName = "BNFProduction"]
      [#set production = expansion.parent]
    [/#if]
    [#if grammar.treeBuildingEnabled]
      [#set buildTreeNode = (treeNodeBehavior?is_null && production?? && !grammar.nodeDefaultVoid)
                        || (treeNodeBehavior?? && !treeNodeBehavior.neverInstantiated)]
    [/#if]
    [#if buildTreeNode]
        [@setupTreeVariables .scope /]
      [@createNode treeNodeBehavior nodeVarName /]
          ParseException ${parseExceptionVar} = null;
          [#--set callStackSizeVar = "callStackSize" + CU.newID()--]
          [#set callStackSizeVar = CU.newVarName("callStackSize")]
          int ${callStackSizeVar} = parsingStack.size();
        [#-- We want the very first java code block in a production 
         to be injected *before* the try block. This is for rather hypertechnical 
         reasons. It's that we want any variables defined up top in a production 
         to be visible within the following catch/finally blocks.--]
        ${(production.javaCode)!}
         try {
            if (false) throw new ParseException("Never happens!");
    [#else]
        ${(production.javaCode)!}
    [/#if]
        [@BuildExpansionCode expansion/]
    [#var returnType = (production.returnType)!"void"]
    [#if production?? && returnType == "void"]
        if (trace_enabled) LOGGER.info("Exiting normally from ${production.name}");
    [/#if]
    [#if buildTreeNode]
         }
         catch (ParseException e) { 
             ${parseExceptionVar} = e;
             throw e;
         }
         finally {
             if (${parseExceptionVar} == null) {
                restoreCallStack(${callStackSizeVar});
             }
             if (buildTree) {
                 if (${parseExceptionVar} == null) {
                     closeNodeScope(${nodeVarName}, ${closeCondition});
                     [#list grammar.closeNodeHooksByClass[nodeClassName(treeNodeBehavior)]! as hook]
                        ${hook}(${nodeVarName});
                     [/#list]
                 } else {
                     if (trace_enabled) LOGGER.warning("ParseException: " + ${parseExceptionVar}.getMessage());
                     clearNodeScope();
                 }
             }
             this.currentlyParsedProduction = prevProduction;
         }       
          ${grammar.utils.popNodeVariableName()!}
    [/#if]
[/#macro]

[#--  A helper macro to set up some variables so that the BuildCode macro can be a bit more readable --]
[#macro setupTreeVariables callingScope]
    [#set nodeNumbering = nodeNumbering +1]
    [#set nodeVarName = currentProduction.name + nodeNumbering in callingScope]
    ${grammar.utils.pushNodeVariableName(callingScope.nodeVarName)!}
    [#set parseExceptionVar = "parseException"+nodeNumbering in callingScope]
    [#if !callingScope.treeNodeBehavior??]
        [#if grammar.smartNodeCreation]
           [#set treeNodeBehavior = {"name" : callingScope.production.name, "condition" : "1", "gtNode" : true, "void" :false} in callingScope]
        [#else]
           [#set treeNodeBehavior = {"name" : callingScope.production.name, "condition" : null, "gtNode" : false, "void" : false} in callingScope]
        [/#if]
     [/#if]
     [#if callingScope.treeNodeBehavior.condition?has_content]
       [#set closeCondition = callingScope.treeNodeBehavior.condition in callingScope]
       [#if callingScope.treeNodeBehavior.gtNode]
          [#set closeCondition = "nodeArity() > " + callingScope.closeCondition in callingScope]
       [/#if]
    [/#if]
[/#macro]

[#--  Boilerplate code to create the node variable --]
[#macro createNode treeNodeBehavior nodeVarName]
   [#var nodeName = nodeClassName(treeNodeBehavior)]
   ${nodeName} ${nodeVarName} = null;
   if (buildTree) {
     ${nodeVarName} = new ${nodeName}();
  [#if grammar.nodeUsesParser]
     ${nodeVarName}.setParser(this);
  [/#if]
   
      ${nodeVarName}.setInputSource(getInputSource());
       openNodeScope(${nodeVarName});
  }
[/#macro]

[#function nodeClassName treeNodeBehavior]
   [#if treeNodeBehavior?? && treeNodeBehavior.nodeName??] 
      [#return NODE_PREFIX + treeNodeBehavior.nodeName]
   [/#if]
   [#return NODE_PREFIX + currentProduction.name]
[/#function]


[#macro BuildExpansionCode expansion]
    [#var classname=expansion.simpleName]
    [#if classname = "CodeBlock"]
       ${expansion}
    [#elseif classname="LexicalStateSwitch"] 
       [@BuildCodeLexicalStateSwitch expansion /]
    [#elseif classname = "Failure"]
       [@BuildCodeFailure expansion/]
    [#elseif classname = "ExpansionSequence"]
       [@BuildCodeSequence expansion/]
    [#elseif classname = "NonTerminal"]
       [@BuildCodeNonTerminal expansion/]
    [#elseif expansion.isRegexp]
       [@BuildCodeRegexp expansion/]
    [#elseif classname = "TryBlock"]
       [@BuildCodeTryBlock expansion/]
    [#elseif classname = "AttemptBlock"]
       [@BuildCodeAttemptBlock expansion /]
    [#elseif classname = "ZeroOrOne"]
       [@BuildCodeZeroOrOne expansion/]
    [#elseif classname = "ZeroOrMore"]
       [@BuildCodeZeroOrMore expansion/]
    [#elseif classname = "OneOrMore"]
        [@BuildCodeOneOrMore expansion/]
    [#elseif classname = "ExpansionChoice"]
        [@BuildCodeChoice expansion/]
    [#elseif classname = "Assertion"]
        [@BuildAssertionCode expansion/]
    [/#if]
[/#macro]

[#macro BuildCodeLexicalStateSwitch switch]
    token_source.switchTo(LexicalState.${switch.lexicalStateName});
[/#macro]

[#macro BuildCodeFailure fail]
    [#if fail.code?is_null]
       if (true) throw new ParseException(this, "${fail.message?j_string}");
    [#else]
       ${fail.code}
    [/#if]
[/#macro]

[#macro BuildCodeSequence expansion]
       [#list expansion.units as subexp]
           [@BuildCode subexp/]
       [/#list]        
[/#macro]

[#macro BuildCodeRegexp regexp]
       [#if regexp.LHS??]
          ${regexp.LHS} =  
       [/#if]
   [#if !grammar.faultTolerant]
       consumeToken(${CU.TT}${regexp.label});
   [#else]
       [#var tolerant = regexp.tolerantParsing?string("true", "false")]
       consumeToken(${CU.TT}${regexp.label}, ${tolerant});
   [/#if]
[/#macro]

[#macro BuildCodeTryBlock tryblock]
   [#var nested=tryblock.nestedExpansion]
       try {
          [@BuildCode nested/]
       }
   [#list tryblock.catchBlocks as catchBlock]
       ${catchBlock}
   [/#list]
       ${tryblock.finallyBlock!}
[/#macro]


[#macro BuildCodeAttemptBlock attemptBlock]
   [#var nested=attemptBlock.nestedExpansion]
       try {
          stashParseState();
          [@BuildCode nested/]
          popParseState();
       }
       catch (ParseException e) {
           restoreStashedParseState();
           [#if attemptBlock.recoveryCode??]
              ${attemptBlock.recoveryCode}
           [/#if]
           [#if attemptBlock.recoveryExpansion??]
               [@BuildCode attemptBlock.recoveryExpansion /]
           [#else]
               if (false) throw new ParseException("Never happens!");
           [/#if]
       }
[/#macro]

[#macro BuildCodeNonTerminal nonterminal]
   pushOntoCallStack("${nonterminal.containingProduction.name}", "${nonterminal.inputSource?j_string}", ${nonterminal.beginLine}, ${nonterminal.beginColumn}); 
   try {
   [#if !nonterminal.LHS?is_null]
       ${nonterminal.LHS} = 
   [/#if]
      ${nonterminal.name}(${nonterminal.args!});
    } 
    finally {
        popCallStack();
    }
[/#macro]


[#macro BuildCodeZeroOrOne zoo]
    [#if zoo.nestedExpansion.alwaysSuccessful
      || zoo.nestedExpansion.class.simpleName = "ExpansionChoice"]
       [@BuildCode zoo.nestedExpansion /]
    [#else]
       if (${ExpansionCondition(zoo.nestedExpansion)}) {
          ${BuildCode(zoo.nestedExpansion)}
       }
    [/#if]
[/#macro]

[#var inFirstVarName = "", inFirstIndex =0]

[#macro BuildCodeOneOrMore oom]
   [#var nestedExp=oom.nestedExpansion, prevInFirstVarName = inFirstVarName/]
   [#if nestedExp.simpleName = "ExpansionChoice"]
     [#set inFirstVarName = "inFirst" + inFirstIndex, inFirstIndex = inFirstIndex +1 /]
     boolean ${inFirstVarName} = true; 
   [/#if]
   do {
      [@BuildCode nestedExp/]
      [#if nestedExp.simpleName = "ExpansionChoice"]
         ${inFirstVarName} = false;
      [/#if]
   } 
   [#if nestedExp.simpleName = "ExpansionChoice"]
   while (true);
   [#else]
   while(${ExpansionCondition(oom.nestedExpansion)});
   [/#if]
   [#set inFirstVarName = prevInFirstVarName /]
[/#macro]

[#macro BuildCodeZeroOrMore zom]
    [#if zom.nestedExpansion.class.simpleName = "ExpansionChoice"]
       while (true) {
    [#else]
      while (${ExpansionCondition(zom.nestedExpansion)}) {
    [/#if]
       ${BuildCode(zom.nestedExpansion)}
    }
[/#macro]

[#macro BuildCodeChoice choice]
   [#list choice.choices as expansion]
      [#if expansion.alwaysSuccessful]
         else {
           [@BuildCode expansion /]
         }
         [#return]
      [/#if]
      ${(expansion_index=0)?string("if", "else if")}
      (${ExpansionCondition(expansion)}) { 
         ${BuildCode(expansion)}
      }
   [/#list]
   [#if choice.parent.simpleName == "ZeroOrMore"]
      else {
         break;
      }
   [#elseif choice.parent.simpleName = "OneOrMore"]
       else if (${inFirstVarName}) {
           pushOntoCallStack("${currentProduction.name}", "${choice.inputSource?j_string}", ${choice.beginLine}, ${choice.beginColumn});
           throw new ParseException(this, ${choice.firstSetVarName}, parsingStack);
       } else {
           break;
       }
   [#elseif choice.parent.simpleName != "ZeroOrOne"]
       else {
           pushOntoCallStack("${currentProduction.name}", "${choice.inputSource?j_string}", ${choice.beginLine}, ${choice.beginColumn});
           throw new ParseException(this, ${choice.firstSetVarName}, parsingStack);
        }
   [/#if]
[/#macro]

[#-- 
     Macro to generate the condition for entering an expansion
     including the default single-token lookahead
--]
[#macro ExpansionCondition expansion]
    [#if expansion.requiresPredicateMethod]
       ${ScanAheadCondition(expansion)}
    [#else] 
       ${SingleTokenCondition(expansion)}
    [/#if]
[/#macro]


[#-- Generates code for when we need a scanahead --]
[#macro ScanAheadCondition expansion]
   [#if expansion.lookahead?? && expansion.lookahead.LHS??]
      (${expansion.lookahead.LHS} =
   [/#if]
   [#if expansion.hasSemanticLookahead && !expansion.lookahead.semanticLookaheadNested]
      (${expansion.semanticLookahead}) &&
   [/#if]
   ${expansion.predicateMethodName}()
   [#if expansion.lookahead?? && expansion.lookahead.LHS??]
      )
   [/#if]
[/#macro]


[#-- Generates code for when we don't need any scanahead routine --]
[#macro SingleTokenCondition expansion]
   [#if expansion.firstSet.tokenNames?size =0]
      true 
   [#elseif expansion.firstSet.tokenNames?size < 5] 
      [#list expansion.firstSet.tokenNames as name]
          nextTokenType [#if name_index ==0]() [/#if]
          == ${CU.TT}${name} 
         [#if name_has_next] || [/#if] 
      [/#list]
   [#else]
      ${expansion.firstSetVarName}.contains(nextTokenType()) 
   [/#if]
[/#macro]



[#macro BuildAssertionRoutine assertion]
    [#var methodName = assertion.predicateMethodName?replace("scan$", "assert$")]
    [#var empty = true]
    private final void ${methodName}() throws ParseException {
       if (!(
       [#if !assertion.semanticLookahead?is_null]
          (${assertion.semanticLookahead})
          [#set empty = false /]
       [/#if]
       [#if !assertion.lookBehind?is_null]
          [#if !empty] && [/#if]
          !${assertion.lookBehind.routineName}()
       [/#if]
       [#if !assertion.expansion?is_null]
           [#if !empty] && [/#if]
           [#if assertion.expansion.negated] ! [/#if]
           ${assertion.expansion.scanRoutineName}()
       [/#if]
       )) {
          throw new ParseException(this, "${assertion.message?j_string}");
        }
    }
[/#macro]

[#macro BuildAssertionCode assertion]
    [#var empty = true]
       if (!(
       [#if !assertion.semanticLookahead?is_null]
          (${assertion.semanticLookahead})
          [#set empty = false /]
       [/#if]
       [#if !assertion.lookBehind?is_null]
          [#if !empty] && [/#if]
          !${assertion.lookBehind.routineName}()
       [/#if]
       [#if !assertion.expansion?is_null]
           [#if !empty] && [/#if]
           [#if assertion.expansionNegated] ! [/#if]
           ${assertion.expansion.scanRoutineName}()
       [/#if]
       )) {
          throw new ParseException(this, "${assertion.message?j_string}");
        }
[/#macro]
