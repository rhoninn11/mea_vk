#include "stdio.h"
#include "string.h"

#include "raylib.h"
#include "raymath.h"


#define MINICORO_IMPL
#include "minicoro.h"


#define STB_DS_IMPLEMENTATION
#include "stb_ds.h"


#define LOCAL_STACK 2*1024
#define TXT_RED "\x1b[31m"
#define TXT_GREAN "\x1b[32m"
#define TXT_YELLOW "\x1b[33m"
#define TXT_CLEAR "\x1b[0m"

typedef struct{
    Matrix m4x4;
    Vector3 pos;
}PlacementInfo;

char easy_access_stack[LOCAL_STACK];

int colored(char *out, const char *content, const char *txt_color) {
    return sprintf(out, "%s%s%s", txt_color, content, TXT_CLEAR);
}

int printV3(char *out, const Vector3 v) {
    return sprintf(out, "| x = %-6.2f | y = %-6.2f | z = %-6.2f |", v.x, v.y, v.z);
}

void genSomePlacements(PlacementInfo **dynamic_array) {

    for(int i = 0; i < 12; i++) {
        PlacementInfo new_place = {
            .m4x4 = MatrixIdentity(),
            .pos = {.x = (float)i},
        };
        arrput(*dynamic_array, new_place);
        int len = arrlen(*dynamic_array);
    }
}

void readImages(const char *file, PlacementInfo **dynamic_array) {

    char *str_a = &easy_access_stack[0];
    char *str_b = &easy_access_stack[1024];

    FILE* img_file = fopen(file, "rb");
    if (img_file == NULL) {
        colored(str_b, "not exists", TXT_RED);
        colored(str_a, file, TXT_YELLOW);
        printf("!!! error: %s -> %s, so we gen some data\n", str_a, str_b);
        genSomePlacements(dynamic_array);
        return;
    }

    // TODO: implement file reading 
    genSomePlacements(dynamic_array);
    fclose(img_file);
}

int main(void)
{


    InitWindow(800, 600, "raylib cubes");
    SetTargetFPS(60);

    Camera3D camera = {
        .position   = (Vector3){5.0f, 5.0f, 5.0f},
        .target     = (Vector3){0.0f, 0.0f, 0.0f},
        .up         = (Vector3){0.0f, 1.0f, 0.0f},
        .fovy       = 45.0f,
        .projection = CAMERA_PERSPECTIVE,
    };

    Color colors[] = {RED, GREEN, BLUE, YELLOW, ORANGE, PURPLE, PINK, SKYBLUE};
    Vector3 positions[] = {
        {-1.5f, 0, -1.5f}, { 1.5f, 0, -1.5f},
        {-1.5f, 0,  1.5f}, { 1.5f, 0,  1.5f},
        {-1.5f, 2,  -1.5f}, { 1.5f, 2, -1.5f},
        {-1.5f, 2,   1.5f}, { 1.5f, 2,  1.5f},
    };

    float angle = 0.0f;
    float radius = 8.0f;

        
    char *some_info = &easy_access_stack[0];

    PlacementInfo* img_placements = NULL;
    arrsetcap(img_placements, 8); //example init
    //as we passing **TYPENAME inittialization 
    //could be done without memory leak inside function
    readImages("fs/images.txt", &img_placements); 

    int img_num = arrlen(img_placements);
    printf("recorded (%d)\n", img_num);
    for(int i = 0; i < img_num; i++) {
        printV3(some_info, img_placements[i].pos);
        printf("Img (%4d) at %s\n", i, some_info);
    } 



    colored(some_info, "is looping", TXT_GREAN);
    printf("+++ main loop %s\n", some_info);
    while (!WindowShouldClose()) {
        angle += 0.5f * GetFrameTime();
        camera.position = (Vector3){
            cosf(angle) * radius,
            5.0f,
            sinf(angle) * radius,
        };

        BeginDrawing();
        ClearBackground(RAYWHITE);

        BeginMode3D(camera);
        for (int i = 0; i < 8; i++) {
            DrawCube(positions[i], 1.0f, 1.0f, 1.0f, colors[i]);
            DrawCubeWires(positions[i], 1.0f, 1.0f, 1.0f, BLACK);
        }
        DrawGrid(10, 1.0f);
        EndMode3D();

        DrawText("Hello World!", 10, 10, 20, DARKGRAY);
        EndDrawing();
    }

    CloseWindow();
    return 0;
}