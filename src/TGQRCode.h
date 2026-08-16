//
// TGQRCode - a byte-mode QR encoder.
//
// The block geometry, alignment-pattern positions and error-correction
// parameters all come out of quirc's version database, which we already
// vendor for the scanner: encoder and decoder therefore cannot drift apart.
// Error-correction levels use quirc's numbering (QUIRC_ECC_LEVEL_*), which
// happens to be the same numbering the format-information field uses.
//
#ifndef TGQRCODE_H_
#define TGQRCODE_H_

#include <stdint.h>

typedef struct {
	int size;
	uint8_t *modules;
} TGQRMatrix;

int TGQRCodeEncodeBytes(const uint8_t *bytes, int length, int eccLevel,
                        TGQRMatrix *out);
int TGQRCodeEncodeString(const char *text, int eccLevel, TGQRMatrix *out);
void TGQRMatrixRelease(TGQRMatrix *matrix);

#endif
