/* Copyright (c) 2008-2021 Jonathan Revusky, revusky@javacc.com
 * Copyright (c) 2006, Sun Microsystems Inc.
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
 *       nor the names of any contributors may be used to endorse or promote
 *       products derived from this software without specific prior written
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

package com.javacc.lexgen;

import java.util.*;

import com.javacc.Grammar;
import com.javacc.parsegen.RegularExpression;

/**
 * Class representing a single state of a Non-deterministic Finite Automaton (NFA)
 * Note that any given lexical state is implemented as an NFA (and a DFA for string literals)
 * Thus, any given NfaState object is associated with one lexical state.
 */
public class NfaState {  

    private final Grammar grammar;
    private final LexerData lexerData;
    private final LexicalStateData lexicalState;
    private final NfaData nfaData;
    private RegularExpression type;
    private Set<NfaState> epsilonMoves = new HashSet<>();
    private BitSet asciiMoves = new BitSet();
    private List<Integer> rangeMovesLeftSide = new ArrayList<>();
    private List<Integer> rangeMovesRightSide = new ArrayList<>();
    private NfaState next;
    private boolean isFinal;
    private int nonAsciiMethod = -1;
    private List<Integer> nonAsciiMoveIndices;
    private List<Integer> loByteVec = new ArrayList<>();
    private int inNextOf;

    // What a Rube Goldberg contraption this is!
    // In general, any time the index value is used, 
    // we should be using a direct reference to this NfaState object
    // And any references to the so-called epsilonMovesString 
    // usually as a map key should
    // also be a reference to the NfaState object.
    // It's as if the person who wrote this code thought that the only 
    // key->value arrangement was String->int or String->int[]
    // Totally bizarre.
    private int index = -1;
//    private String epsilonMovesString;

    NfaState(LexicalStateData lexicalState) {
        this.lexicalState = lexicalState;
        nfaData = lexicalState.getNfaData();
        this.grammar = lexicalState.getGrammar();
        this.lexerData = grammar.getLexerData();
        nfaData.getAllStates().add(this);
    }

    public int getIndex() {
        return index;
    }

    RegularExpression getType() {return type;}

    void setType(RegularExpression type) {
        this.type = type;
    }

    void setFinal(boolean b) {
        this.isFinal = b;
    }

    public int getNonAsciiMethod() {
        return nonAsciiMethod;
    }

    public List<Integer> getNonAsciiMoveIndices() {
        return nonAsciiMoveIndices;
    }

    public List<Integer> getLoByteVec() {
        return loByteVec;
    }

    public long[] getAsciiMoves() {
        long[] ll = asciiMoves.toLongArray();
        if (ll.length !=2) {
            ll = Arrays.copyOf(ll, 2);
        }
        return ll;
    }

    public BitSet getAsciiMoveSet() {
        return asciiMoves;
    }

    List<NfaState> getEpsilonMoves() {
        // REVISIT: The following line does not seem necessary, but I have it there
        // to replicate legacy behavior just in case.
//        Collections.sort(epsilonMoves, (state1, state2) -> state1.index-state2.index);
        return new ArrayList<>(epsilonMoves);
    }
    
    boolean hasAsciiMove(int c) {
        return asciiMoves.get(c);
    }

    public int getInNextOf() {
        return inNextOf;
    }

    void incrementInNextOf() {
        this.inNextOf++;
    }

    public LexicalStateData getLexicalState() {
        return lexicalState;
    }

    public NfaState getNext() {
        return next;
    }

    void setNext(NfaState next) {
        this.next = next;
    }

    public int getKindToPrint() {
        return next.type == null ? Integer.MAX_VALUE : next.type.getOrdinal();
    }

    public int getEpsilonMoveCount() {
        return epsilonMoves.size();
    }

    public boolean isNeeded(int byteNum) {
        if (byteNum < 0) {
            return isNeededNonAscii();
        }
        return byteNum == 0 ? asciiMoves.previousSetBit(63) >=0 : asciiMoves.nextSetBit(64) >=64; 
    }

    public boolean isNeededNonAscii() {
        return nonAsciiMethod != -1;
    }

    void addEpsilonMove(NfaState newState) {
        epsilonMoves.add(newState);
    }

    void addCharMove(int c) {
        addRange(c, c);
    }

    void addRange(int left, int right) {
        assert right>=left;
        for (int c = left; c <=right && c<128; c++) {
            asciiMoves.set(c);
        }
        left = Math.max(left, 128);
        if (right >= left) {
            rangeMovesLeftSide.add(left);
            rangeMovesRightSide.add(right);
        }
    }

    private boolean closureDone = false;

    /**
     * This function computes the closure and also updates the kind so that any
     * time there is a move to this state, it can go on epsilon to a new state
     * in the epsilon moves that might have a lower kind of token number for the
     * same length.
     */
    private boolean epsilonClosure() {
        boolean finished = true;
        if (closureDone) {
            return finished;
        }
        closureDone = true;
        // Recursively do closure
        for (NfaState state : new ArrayList<>(epsilonMoves)) {
            finished = state.epsilonClosure();
            if (type == null || (state.type != null && state.type.getOrdinal() < type.getOrdinal())) {
                type = state.type;
            } 
            for (NfaState otherState : state.epsilonMoves) {
                if (otherState.isUsefulState()) {
                    addEpsilonMove(otherState);
                    finished = false;
                } 
            }
        }
        if (hasTransitions()) {
            addEpsilonMove(this);
        }
        return finished;
    }

    private boolean isUsefulState() {
        return isFinal || hasTransitions();
    }

    public boolean hasTransitions() {
        return !asciiMoves.isEmpty()
                || !rangeMovesLeftSide.isEmpty();
    }
    
    void generateCode() {
        if (index != -1)
            return;
        if (next != null) {
            next.generateCode();
        }
        if (index == -1 && hasTransitions()) {
            this.index = lexicalState.getIndexedAllStates().size();
            lexicalState.getIndexedAllStates().add(this);
            next.getEpsilonMovesString();
        }
    }

    void optimizeEpsilonMoves() { 
        while (!epsilonClosure());
        epsilonMoves.removeIf(state->!state.hasTransitions());
    }

    public String getEpsilonMovesString() {
        List<NfaState> states = new ArrayList<>();
        if (getEpsilonMoveCount() > 0 && nfaData.getAllNextStateSets().get(this)== null) {
            for (NfaState epsilonMove : epsilonMoves) {
                if (epsilonMove.hasTransitions()) {
                    if (epsilonMove.index == -1) {
                        epsilonMove.generateCode();
                    }
                    lexicalState.getIndexedAllStates().get(epsilonMove.index).inNextOf++;
                    states.add(epsilonMove);
                }
            }
            nfaData.getAllNextStateSets().put(this, states);
        }
        String epsilonMovesString = null;
        if (getEpsilonMoveCount() > 0) {
            int[] stateNames = new int[getEpsilonMoveCount()];
            epsilonMovesString = "{ ";
            int idx =0;
            for (NfaState epsilonMove : epsilonMoves) {
                if (epsilonMove.hasTransitions()) {
                    if (epsilonMove.index == -1) {
                        epsilonMove.generateCode();
                    }
                    lexicalState.getIndexedAllStates().get(epsilonMove.index).inNextOf++;
                    stateNames[idx] = epsilonMove.index;
                    epsilonMovesString += epsilonMove.index + ", ";
                    if (idx++ > 0 && idx % 16 == 0)
                        epsilonMovesString += "\n";
                }
            }
            epsilonMovesString += "};";
            nfaData.getAllNextStates().put(epsilonMovesString, stateNames);            
        }
        return epsilonMovesString;
    }

    final boolean canMoveUsingChar(int c) {
        if (c < 128) {
            return asciiMoves.get(c);
        }
        // Iterate thru the table to see if the current char
        // is in some range
        for (int i=0; i<rangeMovesLeftSide.size(); i++) {
            int left = rangeMovesLeftSide.get(i);
            int right = rangeMovesRightSide.get(i);
            if (c >= left && c <= right) 
                return true;
            else if (c < left || left == 0)
                break;
        }
        return false;
    }

    int getFirstValidPos(String s, int start, int len) {
        for (int i=start; i< len; i++) {
            if (canMoveUsingChar(s.codePointAt(i))) {
                return i;
            }
        }
        return len;
    }

    int moveFrom(int c, List<NfaState> newStates) {
        if (canMoveUsingChar(c)) {
            newStates.addAll(next.epsilonMoves);
            return getKindToPrint();
        }
        return Integer.MAX_VALUE;
    }

    /*
     * This function generates the bit vectors of low and hi bytes for common
     * bit vectors and returns those that are not common with anything (in
     * loBytes) and returns an array of indices that can be used to generate the
     * function names for char matching using the common bit vectors. It also
     * generates code to match a char with the common bit vectors. (Need a
     * better comment).
     * FIXME! Need to replace all the char with int
     * Also it is long overdue to rewrite this ugly legacy code anyway!
     * Im pretty sure that the following method can be written in 
     * far fewer lines!
     */
    void generateNonAsciiMoves() {
        if (rangeMovesLeftSide.isEmpty()) {
            return;
        }
        BitSet charMoves = new BitSet();
        for (int i=0; i< rangeMovesLeftSide.size(); i++) {
            int leftSide = rangeMovesLeftSide.get(i);
            int rightSide = rangeMovesRightSide.get(i);
            while (leftSide<=rightSide) {
                charMoves.set(leftSide++);
            }
        }
        BitSet superfluousSubsets = new BitSet();
        nonAsciiMoveIndices = new ArrayList<>();
        // The following 40-odd lines of code constitute a space
        // optimization. Commenting it all out produces
        // larger (redundant) XXXLexer.java files, but it all still works!
        for (int i = 0; i < 0xFF; i++) {
            BitSet commonSet = new BitSet();
            BitSet subSet = charMoves.get(256*i, 256*(i+1));
            if (subSet.isEmpty()) {
                superfluousSubsets.set(i);
            }
            if (superfluousSubsets.get(i)) {
                continue;
            }
            for (int j = i + 1; j <= 0xFF; j++) {
                if (!superfluousSubsets.get(j)) {
                    if (subSet.equals(charMoves.get(256*j, 256*(j+1)))) {
                        superfluousSubsets.set(j);
                        if (commonSet.isEmpty()) {
                            superfluousSubsets.set(i);
                            commonSet.set(i);
                        }
                        commonSet.set(j);
                    }
                }
            }
            if (!commonSet.isEmpty()) {
                Integer ind;
                String bitVector = bitSetToLong(commonSet);
                Map<String, Integer> lohiByteTable = lexerData.getLoHiByteTable();
                List<String> allBitVectors = lexerData.getAllBitVectors();
                if ((ind = lohiByteTable.get(bitVector)) == null) {
                    allBitVectors.add(bitVector);

                    int lohiByteCount = lexerData.getLohiByteCount();
                    lohiByteTable.put(bitVector, ind = lohiByteCount);
                    lexerData.incrementLohiByteCount();
                }
                nonAsciiMoveIndices.add(ind);
                bitVector = bitSetToLong(subSet);
                if ((ind = lohiByteTable.get(bitVector)) == null) {
                    allBitVectors.add(bitVector);
                    int lohiByteCount = lexerData.getLohiByteCount();
                    lohiByteTable.put(bitVector, ind = lohiByteCount);
                    lexerData.incrementLohiByteCount();
                }
                nonAsciiMoveIndices.add(ind);
            }
        }
// Up to here is just a space optimization. (Gradually coming to an understanding of this...)
// Without the space optimization, the nonAsciiMoveIndices array is empty
        for (int i = 0; i < 256; i++) {
            if (!superfluousSubsets.get(i)) {
                Map<String, Integer> lohiByteTable = lexerData.getLoHiByteTable();
                BitSet subSet = charMoves.get(256*i, 256*(i+1));
                String longsString = bitSetToLong(subSet);
                List<String> allBitVectors = lexerData.getAllBitVectors();
                Integer ind = lohiByteTable.get(longsString);
                if (ind == null) {
                    allBitVectors.add(longsString);
                    int lohiByteCount = lexerData.getLohiByteCount();
                    lohiByteTable.put(longsString, ind = lohiByteCount);
                    lexerData.incrementLohiByteCount();
                }
                loByteVec.add(i);
                loByteVec.add(ind);
            }
        }
        updateDuplicateNonAsciiMoves();
    }

    static private String bitSetToLong(BitSet bs) {
        long[] longs = bs.toLongArray();
        longs = Arrays.copyOf(longs, 4);
        return "{0x" + Long.toHexString(longs[0]) + "L,0x"
               + Long.toHexString(longs[1]) + "L,0x"
               + Long.toHexString(longs[2]) + "L,0x"
               + Long.toHexString(longs[3]) + "L}";
    }

    private void updateDuplicateNonAsciiMoves() {
        List<NfaState> nonAsciiTableForMethod = lexerData.getNonAsciiTableForMethod();
        for (int i = 0; i < nonAsciiTableForMethod.size(); i++) {
            NfaState state = nonAsciiTableForMethod.get(i);
            if (loByteVec != null && loByteVec.equals(state.loByteVec) 
                    && nonAsciiMoveIndices != null 
                    && nonAsciiMoveIndices.equals(state.nonAsciiMoveIndices)) {
                nonAsciiMethod = i;
                return;
            }
        }
        nonAsciiMethod = nonAsciiTableForMethod.size();
        nonAsciiTableForMethod.add(this);
    }

    void generateInitMoves() {
        String epsilonMovesString = getEpsilonMovesString();
        if (epsilonMovesString == null)
            epsilonMovesString = "null;";
        nfaData.addStartStateSet(epsilonMovesString);
    }

    boolean intersects(NfaState other) {
        Set<NfaState> tempSet = new HashSet<>(epsilonMoves);
        tempSet.retainAll(other.epsilonMoves);
        return !tempSet.isEmpty();
    }
    
    public boolean isNextIntersects() {
        for (NfaState state : nfaData.getAllStates()) {
            if (this == state || state.index == -1 || index == state.index
                    || (state.nonAsciiMethod == -1))
                continue;
            if (intersects(state.next)) {
                return true;
            }
        }
        return false;
    }

    private boolean isMoveState(NfaState other, int byteNum) {
        if (this.next.type != other.next.type) {
            return false;
        }
        if (byteNum < 0 && this.nonAsciiMethod != other.nonAsciiMethod) {
            return false;
        }
        if (byteNum >=0 && !this.asciiMoves.equals(other.asciiMoves)) {
            return false;
        }
        if (this.next.epsilonMoves.isEmpty() || other.next.epsilonMoves.isEmpty()) {
            return false;
        }
        return this.next.epsilonMoves.equals(other.next.epsilonMoves);
    }

    public List<NfaState> getMoveStates(int byteNum, BitSet statesAlreadyHandled) {
        List<NfaState> result = new ArrayList<NfaState>();
        for (NfaState state : nfaData.getAllStates()) {
            if (!statesAlreadyHandled.get(state.index) && isMoveState(state, byteNum)) {
                statesAlreadyHandled.set(state.index);
                result.add(state);
            }
        }
        return result;
    }

    /**
     * @param byteNum
     *            either 0 or 1
     */
    public boolean isOnlyState(int byteNum) {
        for (NfaState state : nfaData.getAllStates()) {
            BitSet bs = new BitSet();
            bs.or(asciiMoves);
            bs.and(state.asciiMoves);
            boolean intersects = bs.cardinality() > 0;
            if (intersects) {
                intersects = byteNum == 0 ? bs.previousSetBit(63) >=0 : bs.nextSetBit(64) >=0;
            }
            if (state.index != -1 && state.index != this.index && state.isNeeded(byteNum) && intersects) {
                return false;
            }
        }
        return true;
    }
}
