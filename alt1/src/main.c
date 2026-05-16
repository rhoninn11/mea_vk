#include "stdio.h"
#include "string.h"

#define MINICORO_IMPL
#include "minicoro.h"

#define LOCAL_STACK 2048

void colored(char *out, const char *content) {
    int num = sprintf(out, "\x1b[31m%s\x1b[0m", content);
}

int main() {
    char some_stack_memory[LOCAL_STACK];
    char *col_text = some_stack_memory;
    colored(col_text, "with painted text");
    printf("+++ hello world %s\n", col_text);
    return 0;
}