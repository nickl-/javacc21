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
 *     * Neither the name Jonathan Revusky nor the names of any other  
 *       contributors may be used to endorse or promote productrs derived 
 *       from this software without specific prior written permission.
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
package com.javacc.output.java;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

import com.javacc.parser.JavaCCParser;
import com.javacc.parser.ParseException;
import com.javacc.parser.tree.CompilationUnit;

/**
 * Tests for {@link JavaFormatter}.
 * 
 * @author Angelo ZERR
 *
 */
public class JavaFormatterTest {

	@Test
	public void formatMethod() throws ParseException {
		assertFormat( //
				"package com.javacc;\n" + //
						"\n" + //
						"public class Foo {\n" + //
						"\n" + //
						"	@Override\n" + //
						"	public String toString() {\n" + //
						"		return super.toString();\n" + //
						"	}\n" + //
						"}\n" + //
						"", //
				"package com.javacc;\n" + //
						"\n" + //
						"public class Foo {\n" + //
						"    @Override\n" + //
						"    public String toString() {\n" + //
						"        return super.toString();\n" + //
						"    }\n" + //
						"\n" + //
						"}\n" + //
						"");
	}

	public static void assertFormat(String content, String expected) throws ParseException {
		String actual = format("test.java", content);
		assertEquals(expected, actual);
	}

	private static String format(String inputSource, CharSequence content) throws ParseException {
		CompilationUnit unit = JavaCCParser.parseJavaFile(inputSource, content);
		JavaFormatter formatter = new JavaFormatter();
		return formatter.format(unit);
	}
}
