[#ftl strict_vars=true]
[#--
/* Copyright (c) 2020, 2021 Jonathan Revusky, revusky@javacc.com
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *     * Redistributions of source code must retain the above copyright notices,
 *       this list of conditions and the following disclaimer.
 *     * Redistributions in binary formnt must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name Jonathan Revusky
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
/* Generated by: ${generated_by}. ${filename} */

[#if grammar.parserPackage?has_content]
package ${grammar.parserPackage};
[/#if]

import java.io.IOException;
import java.io.Reader;
import java.util.Arrays;
import java.util.BitSet;
import java.util.HashMap;
import java.util.Map;
import java.nio.charset.Charset;

/**
 * Rather bloody-minded implementation of a class to read in a file 
 * and store the contents in a String, and keep track of where the lines are. 
 * N.B. It now has a lot of ugly details relating to extended unicode, 
 * i.e. code units vs. code points. The column locations vended to the 
 * lexer machinery are now in terms of code points. (Which are the same as 
 * relative to code units if you have no supplementary unicode characters!) 
 */
@SuppressWarnings("unused")
public class FileLineMap {

    // Munged content, possibly replace unicode escapes, tabs, or CRLF with LF.
    private final CharSequence content;
    // Typically a filename, I suppose.
    private String inputSource;
    // A list of offsets of the beginning of lines
    private final int[] lineOffsets;
    private int startingLine, startingColumn;
    private int bufferPosition;


    // If this is set, it determines 
    // which lines in the file are actually processed.
    private BitSet parsedLines;

    /**
     * This is used in conjunction with having a preprocessor.
     * We set which lines are actually parsed lines and the 
     * unset ones are ignored. Note that this BitSet (unlike most of the rest of the API)
     * uses zero-based (not 1-based) logic
     * @param parsedLines a #java.util.BitSet that holds which lines
     * are parsed (i.e. not ignored)
     */
    public void setParsedLines(BitSet parsedLines) {
        this.parsedLines = parsedLines;
    }
    
    [#var TABS_TO_SPACES = 0, PRESERVE_LINE_ENDINGS="true", JAVA_UNICODE_ESCAPE="false", ENSURE_FINAL_EOL = grammar.ensureFinalEOL?string("true", "false")]
    [#if grammar.settings.TABS_TO_SPACES??]
       [#set TABS_TO_SPACES = grammar.settings.TABS_TO_SPACES]
    [/#if]
    [#if grammar.settings.PRESERVE_LINE_ENDINGS?? && !grammar.settings.PRESERVE_LINE_ENDINGS]
       [#set PRESERVE_LINE_ENDINGS = "false"]
    [/#if]
    [#if grammar.settings.JAVA_UNICODE_ESCAPE?? && grammar.settings.JAVA_UNICODE_ESCAPE]
       [#set JAVA_UNICODE_ESCAPE = "true"]
    [/#if]

    /**
     * This constructor may not be used much soon. Pretty soon all the generated API
     * will tend to use #java.nio.file.Path rather than java.io classes like Reader
     * @param inputSource the lookup name of this FileLineMap
     * @param reader The input to read from
     * @param startingLine location info used in error reporting, this is 1 typically, assuming
     * we started reading at the start of the file.
     * @param startingColumn location info used in error reporting, this is 1 typically, assuming
     * we started reading at the start of the file.
     */
    public FileLineMap(String inputSource, Reader reader, int startingLine, int startingColumn) {
        this(inputSource, readToEnd(reader), startingLine, startingColumn);
    }

    /**
     * Constructor that takes a String or string-like object as the input
     * @param inputSource the lookup name of this FileLineMap
     * @param content The input to read from
     */
    public FileLineMap(String inputSource, CharSequence content) {
        this(inputSource, content, 1, 1);
    }

    /**
     * Constructor that takes a String or string-like object as the input
     * @param inputSource the lookup name of this FileLineMap
     * @param content The input to read from
     * @param startingLine location info used in error reporting, this is 1 typically, assuming
     * we started reading at the start of the file.
     * @param startingColumn location info used in error reporting, this is 1 typically, assuming
     * we started reading at the start of the file.
     */
    public FileLineMap(String inputSource, CharSequence content, int startingLine, int startingColumn) {
        setInputSource(inputSource);
        this.content = mungeContent(content, ${TABS_TO_SPACES}, ${PRESERVE_LINE_ENDINGS}, ${JAVA_UNICODE_ESCAPE}, ${ENSURE_FINAL_EOL});
        this.lineOffsets = createLineOffsetsTable(this.content);
        this.startingLine = startingLine;
        this.startingColumn = startingColumn;
    }

    public int getLineCount() {
        return lineOffsets.length;
    }

    int getLineFromOffset(int pos) {
        if (pos >= content.length()) {
            if (content.charAt(content.length()-1) == '\n') {
                return startingLine + lineOffsets.length;
            }
            return startingLine + lineOffsets.length-1;
        }
        int bsearchResult = Arrays.binarySearch(lineOffsets, pos);
        if (bsearchResult>=0) {
            return startingLine + bsearchResult;
        }
        return startingLine-(bsearchResult+2);
    }

    int getCodeUnitColumnFromOffset(int pos) {
        if (pos >= content.length()) return 1;
        int line = getLineFromOffset(pos)-startingLine;
        return 1+pos-lineOffsets[line];
    }

    int getCodePointColumnFromOffset(int pos) {
        if (pos >= content.length()) return 1;
        if (Character.isLowSurrogate(content.charAt(pos))) --pos;
        int line = getLineFromOffset(pos)-startingLine;
        int lineStart = lineOffsets[line];
        int numSupps = numSupplementaryCharactersInRange(lineStart, pos);
        return 1+pos-lineOffsets[line]-numSupps;
    }
    
    // Now some methods to fulfill the functionality that used to be in that
    // SimpleCharStream class
    /**
     * Backup a certain number of characters
     * This method is dead simple by design and does not handle any of the messiness
     * with column numbers relating to tabs or unicode escapes. 
     * @param amount the number of characters (code points) to backup.
     */
    public void backup(int amount) {
        for (int i=0; i<amount; i++) {
            --bufferPosition;
            char ch = content.charAt(bufferPosition);
            if (bufferPosition > 0 && Character.isLowSurrogate(ch)) {
                if (Character.isHighSurrogate(content.charAt(bufferPosition-1))) {
                    --bufferPosition;
                }
            }
            if (ch == '\n' && parsedLines != null) skipUnparsedLinesBackward();
        }
    }
    
    void forward(int amount) {
        for (int i=0; i<amount; i++) {
            boolean eol = content.charAt(bufferPosition) == '\n';
            ++bufferPosition;
            char ch = content.charAt(bufferPosition);
            if (Character.isLowSurrogate(ch)) {
                if (Character.isHighSurrogate(content.charAt(bufferPosition-1))) {
                    ++bufferPosition;
                }
            }
            if (eol && parsedLines != null) skipUnparsedLinesForward();
        }
    }

    int getEndColumn() {
        return getCodePointColumnFromOffset(bufferPosition-1);
    }
    
    int readChar() {
        if (bufferPosition >= content.length()) {
            return -1;
        }
        char ch = content.charAt(bufferPosition++);
        if (Character.isHighSurrogate(ch) && bufferPosition < content.length()) {
            char nextChar = content.charAt(bufferPosition);
            if (Character.isLowSurrogate(nextChar)) {
                ++bufferPosition;
                return Character.toCodePoint(ch, nextChar);
            }
        }
        if (ch == '\n' && parsedLines != null) {
            skipUnparsedLinesForward();
        }
        return ch;
    }

    private void skipUnparsedLinesForward() {
        int line = getLineFromOffset(bufferPosition);
        int nextParsedLine = parsedLines.nextSetBit(line);
        if (nextParsedLine == -1) {
            bufferPosition = content.length();
        }
        else {
            bufferPosition = lineOffsets[nextParsedLine-startingLine];
        }
    }

    private void skipUnparsedLinesBackward() {
        int  line = getLineFromOffset(bufferPosition);
        int prevParsedLine = parsedLines.previousSetBit(line);
        if (prevParsedLine == -1) {
            bufferPosition =0;
        }
        else {
            bufferPosition = lineOffsets[1+prevParsedLine-startingLine] -1;
        }
    }

    int getLine() {
        return getLineFromOffset(bufferPosition);
    }

    int getColumn() {
        return getCodePointColumnFromOffset(bufferPosition);
    }

    int getBufferPosition() {return bufferPosition;}

    int getEndLine() {
        int line = getLineFromOffset(bufferPosition);
        int column = getCodePointColumnFromOffset(bufferPosition);
        return column == 1 ? line -1 : line;
    }

    // But there is no goto in Java!!!

    void goTo(int offset) {
        this.bufferPosition = offset;
    }

    /**
     * @return the line length in code _units_
     */ 
    private int getLineLength(int lineNumber) {
        int startOffset = getLineStartOffset(lineNumber);
        int endOffset = getLineEndOffset(lineNumber);
        return 1+endOffset - startOffset;
    }

    /**
     * The number of supplementary unicode characters in the specified 
     * offset range. The range is expressed in code units
     */
    private int numSupplementaryCharactersInRange(int start, int end) {
        int result =0;
        while (start < end-1) {
            if (Character.isHighSurrogate(content.charAt(start++))) {
                if (Character.isLowSurrogate(content.charAt(start))) {
                    start++;
                    result++;
                }
            }
        }
        return result;
    }

    /**
     * The offset of the start of the given line. This is in code units
     */
    private int getLineStartOffset(int lineNumber) {
        int realLineNumber = lineNumber - startingLine;
        if (realLineNumber <=0) {
            return 0;
        }
        if (realLineNumber >= lineOffsets.length) {
            return content.length();
        }
        return lineOffsets[realLineNumber];
    }

    /**
     * The offset of the end of the given line. This is in code units.
     */
    private int getLineEndOffset(int lineNumber) {
        int realLineNumber = lineNumber - startingLine;
        if (realLineNumber <0) {
            return 0;
        }
        if (realLineNumber >= lineOffsets.length) {
            return content.length();
        }
        if (realLineNumber == lineOffsets.length -1) {
            return content.length() -1;
        }
        return lineOffsets[realLineNumber+1] -1;
    }

    /**
     * Given the line number and the column in code points,
     * returns the column in code units.
     */
    private int getCodeUnitColumn(int lineNumber, int codePointColumn) {
        int startPoint = getLineStartOffset(lineNumber);
        int suppCharsFound = 0;
        for (int i=1; i<codePointColumn;i++) {
            char first = content.charAt(startPoint++);
            if (Character.isHighSurrogate(first)) {
                char second = content.charAt(startPoint);
                if (Character.isLowSurrogate(second)) {
                    suppCharsFound++;
                    startPoint++;
                }
            }
        }
        return codePointColumn + suppCharsFound;
    }

    /**
     * @param line the line number
     * @param column the column in code _points_
     * @return the offset in code _units_
     */ 
    private int getOffset(int line, int column) {
        if (line==0) line = startingLine; // REVISIT? This should not be necessary!
        int columnAdjustment = (line == startingLine) ? startingColumn : 1;
        int codeUnitAdjustedColumn = getCodeUnitColumn(line, column);
        columnAdjustment += (codeUnitAdjustedColumn - column);
        return lineOffsets[line - startingLine] + column - columnAdjustment;
    }
    
    // ------------- private utilities method

    // Icky method to handle annoying stuff. Might make this public later if it is
    // needed elsewhere
    private static String mungeContent(CharSequence content, int tabsToSpaces, boolean preserveLines,
            boolean javaUnicodeEscape, boolean ensureFinalEndline) {
        if (tabsToSpaces <= 0 && preserveLines && !javaUnicodeEscape) {
            if (ensureFinalEndline) {
                if (content.length() == 0) {
                    content = "\n";
                } else {
                    int lastChar = content.charAt(content.length()-1);
                    if (lastChar != '\n' && lastChar != '\r') {
                        if (content instanceof StringBuilder) {
                            ((StringBuilder) content).append((char) '\n');
                        } else {
                            StringBuilder buf = new StringBuilder(content);
                            buf.append((char) '\n');
                            content = buf.toString();
                        }
                    }
                }
            }
            return content.toString();
        }
        StringBuilder buf = new StringBuilder();
        // This is just to handle tabs to spaces. If you don't have that setting set, it
        // is really unused.
        int col = 0;
        int index = 0, contentLength = content.length();
        while (index < contentLength) {
            char ch = content.charAt(index++);
            if (ch == '\n') {
                buf.append(ch);
                ++col;
            }
            else if (javaUnicodeEscape && ch == '\\' && index<contentLength && content.charAt(index)=='u') {
                int numPrecedingSlashes = 0;
                for (int i = index-1; i>=0; i--) {
                    if (content.charAt(i) == '\\') 
                        numPrecedingSlashes++;
                    else break;
                }
                if (numPrecedingSlashes % 2 == 0) {
                    buf.append((char) '\\');
                    index++;
                    continue;
                }
                int numConsecutiveUs = 0;
                for (int i = index; i<contentLength; i++) {
                    if (content.charAt(i) == 'u') numConsecutiveUs++;
                    else break;
                }
                String nextFour = content.subSequence(index+numConsecutiveUs, index+numConsecutiveUs+4).toString();
                buf.append((char) Integer.parseInt(nextFour, 16));
                index+=(numConsecutiveUs +4);
            }
            else if (!preserveLines && ch == '\r') {
                buf.append((char)'\n');
                if (index < contentLength && content.charAt(index) == '\n') {
                    ++index;
                    col = 0;
                }
            } else if (ch == '\t' && tabsToSpaces > 0) {
                //justSawUnicodeEscape = false;
                int spacesToAdd = tabsToSpaces - col % tabsToSpaces;
                for (int i = 0; i < spacesToAdd; i++) {
                    buf.append((char) ' ');
                    col++;
                }
            } else {
                buf.append(ch);
                if (!Character.isLowSurrogate(ch)) col++;
            }
        }
        if (ensureFinalEndline) {
            if (buf.length() ==0) {
                return "\n";
            }
            char lastChar = buf.charAt(buf.length()-1);
            if (lastChar != '\n' && lastChar!='\r') buf.append((char) '\n');
        }
        return buf.toString();
    }

    private static int[] createLineOffsetsTable(CharSequence content) {
        if (content.length() == 0) {
            return new int[0];
        }
        int lineCount = 0;
        int length = content.length();
        for (int i = 0; i < length; i++) {
            char ch = content.charAt(i);
            if (ch == '\n') {
                lineCount++;
            }
        }
        if (content.charAt(length - 1) != '\n') {
            lineCount++;
        }
        int[] lineOffsets = new int[lineCount];
        lineOffsets[0] = 0;
        int index = 1;
        for (int i = 0; i < length; i++) {
            char ch = content.charAt(i);
            if (ch == '\n') {
                if (i + 1 == length)
                    break;
                lineOffsets[index++] = i + 1;
            }
        }
        return lineOffsets;
    }


    public String getInputSource() {
        return inputSource;
    }
    
    void setInputSource(String inputSource) {
        this.inputSource = inputSource;
    }

    /**
     * @return the text between startOffset (inclusive)
     * and endOffset(exclusive)
     */
    String getText(int startOffset, int endOffset) {
        return content.subSequence(startOffset, endOffset).toString();
    }

    static private int BUF_SIZE = 0x10000;

    // Annoying kludge really...
    static String readToEnd(Reader reader) {
        try {
            return readFully(reader);
        } catch (IOException ioe) {
            throw new RuntimeException(ioe);
        }
    }

    static String readFully(Reader reader) throws IOException {
        char[] block = new char[BUF_SIZE];
        int charsRead = reader.read(block);
        if (charsRead < 0) {
            throw new IOException("No input");
        } else if (charsRead < BUF_SIZE) {
            char[] result = new char[charsRead];
            System.arraycopy(block, 0, result, 0, charsRead);
            reader.close();
            return new String(block, 0, charsRead);
        }
        StringBuilder buf = new StringBuilder();
        buf.append(block);
        do {
            charsRead = reader.read(block);
            if (charsRead > 0) {
                buf.append(block, 0, charsRead);
            }
        } while (charsRead == BUF_SIZE);
        reader.close();
        return buf.toString();
    }

    /**
     * Rather bloody-minded way of converting a byte array into a string
     * taking into account the initial byte order mark (used by Microsoft a lot seemingly)
     * See: https://docs.microsoft.com/es-es/globalization/encoding/byte-order-markc
     * @param bytes the raw byte array 
     * @return A String taking into account the encoding in the byte order mark (if it was present). If no
     * byte-order mark was present, it assumes the raw input is in UTF-8.
     */
    static public String stringFromBytes(byte[] bytes) {
        int arrayLength = bytes.length;
        int firstByte = arrayLength>0 ? Byte.toUnsignedInt(bytes[0]) : 1;
        int secondByte = arrayLength>1 ? Byte.toUnsignedInt(bytes[1]) : 1;
        int thirdByte = arrayLength >2 ? Byte.toUnsignedInt(bytes[2]) : 1;
        int fourthByte = arrayLength > 3 ? Byte.toUnsignedInt(bytes[3]) : 1;
        if (firstByte == 0xEF && secondByte == 0xBB && thirdByte == 0xBF) {
            return new String(bytes, 3, bytes.length-3, Charset.forName("UTF-8"));
        }
        if (firstByte == 0 && secondByte==0 && thirdByte == 0xFE && fourthByte == 0xFF) {
            return new String(bytes, 4, bytes.length-4, Charset.forName("UTF-32BE"));
        }
        if (firstByte == 0xFF && secondByte == 0xFE && thirdByte == 0 && fourthByte == 0) {
            return new String(bytes, 4, bytes.length-4, Charset.forName("UTF-32LE"));
        }
        if (firstByte == 0xFE && secondByte == 0xFF) {
            return new String(bytes, 2, bytes.length-2, Charset.forName("UTF-16BE"));
        }
        if (firstByte == 0xFF && secondByte == 0xFE) {
            return new String(bytes, 2, bytes.length-2, Charset.forName("UTF-16LE"));
        }
        return new String(bytes, Charset.forName("UTF-8"));
    }
}
