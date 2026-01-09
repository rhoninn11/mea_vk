$env:DIR_PROJ = $PWD

$env:PATH += ";$env:DIR_PROJ\os\win\cmds"
$env:GLFW_LIB = "$env:DIR_PROJ\fs\glfw"
$env:PATH += ";$env:GLFW_LIB\bin"

