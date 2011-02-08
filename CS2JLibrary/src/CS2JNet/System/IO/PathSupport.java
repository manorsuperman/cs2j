/*
   Copyright 2007-2010 Rustici Software, LLC

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

   Author(s):

   Kevin Glynn (kevin.glynn@scorm.com)
*/

package CS2JNet.System.IO;

import java.io.File;

public class PathSupport {

	// Implementation of Path.GetExtension)
	public static String getExtension(String path)
	{
		String fname = new File(path).getName();
		
		int ext_start=fname.lastIndexOf('.');
		
		return (ext_start >= 0?fname.substring(ext_start):"");
	}
	
	public static void main(String[] args)
	{
		System.out.format("getExtension(/tmp/fred.ext) = '%s'\n", PathSupport.getExtension("/tmp/fred.ext"));
		System.out.format("getExtension(/tmp/fred) = '%s'\n", PathSupport.getExtension("/tmp/fred"));
	}
}