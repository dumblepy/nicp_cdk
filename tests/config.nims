import os, strutils

switch("path", "$projectDir")
switch("path", "$projectDir/..")
switch("path", "$projectDir/../src")

let cHeadersPath = "/application/src/c_headers"
switch("passC", "-I" & cHeadersPath)
switch("passL", "-L" & cHeadersPath)
