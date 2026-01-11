#pragma once

#include <lvgl.h>
#include <zephyr/kernel.h>
#include "util.h"

/* Use L8 (8-bit grayscale) - smallest format that supports canvas drawing in LVGL v9 */
#define CANVAS_COLOR_FORMAT LV_COLOR_FORMAT_L8
/* Buffer size: width * height * 1 byte per pixel */
#define CANVAS_BUF_SIZE (SCREEN_WIDTH * SCREEN_HEIGHT)

struct zmk_widget_screen {
    sys_snode_t node;
    lv_obj_t *obj;
    uint8_t cbuf[CANVAS_BUF_SIZE];
    uint8_t cbuf2[CANVAS_BUF_SIZE];
    uint8_t cbuf3[CANVAS_BUF_SIZE];
    struct status_state state;
};

int zmk_widget_screen_init(struct zmk_widget_screen *widget, lv_obj_t *parent);
lv_obj_t *zmk_widget_screen_obj(struct zmk_widget_screen *widget);
