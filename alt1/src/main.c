#include "stdio.h"
#include "string.h"
#include "stdint.h"
#include "math.h"

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
    Quaternion quat;
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
    const int fake_sample_num = 12;
    for(int i = 0; i < fake_sample_num; i++) {
        PlacementInfo new_place = {
            .pos = {.x = (float)i},
        };
        arrput(*dynamic_array, new_place);
        // int len = arrlen(*dynamic_array);
    }
    printf("+++ generated fake samples (%d)\n", fake_sample_num);
}

PlacementInfo readPlacementLine(const char* line_read) {
    PlacementInfo p_info;
    uint32_t img_id, pnt_num;
    char name_buff[256];
    sscanf(line_read, "%d %g %g %g %g %g %g %g %d %255s", //sscanf_s limited for windows
        &img_id, &p_info.quat.w, &p_info.quat.x, &p_info.quat.y, &p_info.quat.z,
        &p_info.pos.x, &p_info.pos.y, &p_info.pos.z, &pnt_num, name_buff);


    // C = -R^T * T  
    Matrix R = QuaternionToMatrix(p_info.quat);
    Vector3 new_pos = Vector3Transform(Vector3Scale(p_info.pos, -1), MatrixTranspose(R));
    p_info.pos = new_pos;


    return p_info;
}

typedef enum{
    RS_PHASE_A = 1,
    RS_PHASE_B = 2,
}READ_STATE;

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
    FILE* img_out = fopen("fs/images_short.txt", "wb");
    bool to_rewrite = img_out != NULL;
    if (!to_rewrite) {
        printf("!!! error: %s -> %s, so we gen some data\n", str_a, str_b);
        genSomePlacements(dynamic_array);
        return;
    }

    // TODO: implement file reading 
    printf("+++ reading a file\n");
    #define BIG_LINE_SIZE 2*1024*1024 //a kto mi zabroni
    char line_buffer[BIG_LINE_SIZE];

    READ_STATE state = RS_PHASE_A;
    while (fgets(line_buffer, BIG_LINE_SIZE, img_file)){
        if (line_buffer[0] == '#'){
            continue;
        }
        if (state == RS_PHASE_A) {
            state = RS_PHASE_B;
            fwrite(line_buffer, 1, strlen(line_buffer), img_out);
            arrput(*dynamic_array, readPlacementLine(line_buffer));
            continue;
        }
        if (state == RS_PHASE_B) {
            state = RS_PHASE_A;
            continue;
        }
    }
    fclose(img_file);
    if (to_rewrite){
        fclose(img_out);
    }
}

int main(void)
{
    InitWindow(1920, 1080, "colmap data preview");
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
    float radius = 16.0f;
    bool rot_flag = true;

        
    char *some_info = &easy_access_stack[0];

    PlacementInfo* img_placements = NULL;
    arrsetcap(img_placements, 8); //example init
    //as we passing **TYPENAME inittialization 
    //could be done without memory leak inside function
    readImages("fs/images.txt", &img_placements); 

    int img_num = arrlen(img_placements);
    int show_num = img_num;
    printf("recorded (%d)\n", img_num);
    if (img_num > 32) show_num = 32;
    for(int i = 0; i < show_num; i++) {
        printV3(some_info, img_placements[i].pos);
        printf("Img (%4d) at %s\n", i, some_info);
    } 

    colored(some_info, "is looping", TXT_GREAN);
    printf("+++ main loop %s\n", some_info);
    while (!WindowShouldClose()) {
        if (IsKeyPressed(KEY_SPACE)) {
            rot_flag = !rot_flag;            
        }

        if (rot_flag) {
            angle += 0.5f * GetFrameTime();
            camera.position = (Vector3){
                cosf(angle) * radius,
                5.0f,
                sinf(angle) * radius,
            };
        } else {
            UpdateCamera(&camera, CAMERA_FREE);
        }

        BeginDrawing();
        ClearBackground(RAYWHITE);

        BeginMode3D(camera);
        for (int i = 0; i < 8; i++) {
            DrawCube(positions[i], 1.0f, 1.0f, 1.0f, colors[i]);
            DrawCubeWires(positions[i], 1.0f, 1.0f, 1.0f, BLACK);
        }
        float cube_size = 0.5f;
        for (int i = 0; i < img_num; i++) {
            PlacementInfo info = img_placements[i];
            DrawCube(info.pos, cube_size, cube_size, cube_size, colors[0]);
        }
        DrawGrid(10, 1.0f);
        EndMode3D();

        DrawText("Hello World!", 10, 10, 20, DARKGRAY);
        EndDrawing();
    }

    CloseWindow();
    return 0;
}