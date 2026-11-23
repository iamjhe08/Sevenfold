//
//  SFErrors.h
//  Sevenfold
//
//  Sevenfold · BY: T4MAG0
//
//  Error codes reported by the signing pipeline.
//

#ifndef SFErrors_h
#define SFErrors_h

#define SFErrorAlreadyUndertakingPipeline 100   // a run is already going
#define SFErrorNoSigningRequired          101   // nothing to sign
#define SFErrorFailedToCopyBundle         102   // couldn't stage the app
#define SFErrorFailedToInstallSignedIPA   103   // iOS refused the signed app

#endif
