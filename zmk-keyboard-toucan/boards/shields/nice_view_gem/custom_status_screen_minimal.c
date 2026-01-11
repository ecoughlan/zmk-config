/*
 * Minimal custom status screen for testing
 */

#include <zephyr/logging/log.h>
LOG_MODULE_DECLARE(zmk, CONFIG_ZMK_LOG_LEVEL);

#include <lvgl.h>
#include <zmk/display.h>

LV_FONT_DECLARE(lv_font_montserrat_16);

lv_obj_t *zmk_display_status_screen() {
    lv_obj_t *screen;
    screen = lv_obj_create(NULL);
    
    // Set background to white
    lv_obj_set_style_bg_color(screen, lv_color_white(), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(screen, LV_OPA_COVER, LV_PART_MAIN);
    
    // Just create a simple label
    lv_obj_t *label = lv_label_create(screen);
    lv_obj_set_style_text_font(label, &lv_font_montserrat_16, LV_PART_MAIN);
    lv_obj_set_style_text_color(label, lv_color_black(), LV_PART_MAIN);
    lv_label_set_text(label, "ZMK");
    lv_obj_align(label, LV_ALIGN_CENTER, 0, 0);

    return screen;
}
