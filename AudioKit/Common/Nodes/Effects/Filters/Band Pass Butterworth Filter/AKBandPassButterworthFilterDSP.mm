//
//  AKBandPassButterworthFilterDSP.mm
//  AudioKit
//
//  Created by Aurelius Prochazka, revision history on Github.
//  Copyright © 2018 AudioKit. All rights reserved.
//

#include "AKBandPassButterworthFilterDSP.hpp"
#import "AKLinearParameterRamp.hpp"

extern "C" AKDSPRef createBandPassButterworthFilterDSP(int nChannels, double sampleRate) {
    AKBandPassButterworthFilterDSP *dsp = new AKBandPassButterworthFilterDSP();
    dsp->init(nChannels, sampleRate);
    return dsp;
}

struct AKBandPassButterworthFilterDSP::_Internal {
    sp_butbp *_butbp0;
    sp_butbp *_butbp1;
    AKLinearParameterRamp centerFrequencyRamp;
    AKLinearParameterRamp bandwidthRamp;
};

AKBandPassButterworthFilterDSP::AKBandPassButterworthFilterDSP() : data(new _Internal) {
    data->centerFrequencyRamp.setTarget(defaultCenterFrequency, true);
    data->centerFrequencyRamp.setDurationInSamples(defaultRampDurationSamples);
    data->bandwidthRamp.setTarget(defaultBandwidth, true);
    data->bandwidthRamp.setDurationInSamples(defaultRampDurationSamples);
}

// Uses the ParameterAddress as a key
void AKBandPassButterworthFilterDSP::setParameter(AUParameterAddress address, AUValue value, bool immediate) {
    switch (address) {
        case AKBandPassButterworthFilterParameterCenterFrequency:
            data->centerFrequencyRamp.setTarget(clamp(value, centerFrequencyLowerBound, centerFrequencyUpperBound), immediate);
            break;
        case AKBandPassButterworthFilterParameterBandwidth:
            data->bandwidthRamp.setTarget(clamp(value, bandwidthLowerBound, bandwidthUpperBound), immediate);
            break;
        case AKBandPassButterworthFilterParameterRampDuration:
            data->centerFrequencyRamp.setRampDuration(value, _sampleRate);
            data->bandwidthRamp.setRampDuration(value, _sampleRate);
            break;
    }
}

// Uses the ParameterAddress as a key
float AKBandPassButterworthFilterDSP::getParameter(uint64_t address) {
    switch (address) {
        case AKBandPassButterworthFilterParameterCenterFrequency:
            return data->centerFrequencyRamp.getTarget();
        case AKBandPassButterworthFilterParameterBandwidth:
            return data->bandwidthRamp.getTarget();
        case AKBandPassButterworthFilterParameterRampDuration:
            return data->centerFrequencyRamp.getRampDuration(_sampleRate);
    }
    return 0;
}

void AKBandPassButterworthFilterDSP::init(int _channels, double _sampleRate) {
    AKSoundpipeDSPBase::init(_channels, _sampleRate);
    sp_butbp_create(&data->_butbp0);
    sp_butbp_init(_sp, data->_butbp0);
    sp_butbp_create(&data->_butbp1);
    sp_butbp_init(_sp, data->_butbp1);
    data->_butbp0->freq = defaultCenterFrequency;
    data->_butbp1->freq = defaultCenterFrequency;
    data->_butbp0->bw = defaultBandwidth;
    data->_butbp1->bw = defaultBandwidth;
}

void AKBandPassButterworthFilterDSP::deinit() {
    sp_butbp_destroy(&data->_butbp0);
    sp_butbp_destroy(&data->_butbp1);
}

void AKBandPassButterworthFilterDSP::process(AUAudioFrameCount frameCount, AUAudioFrameCount bufferOffset) {

    for (int frameIndex = 0; frameIndex < frameCount; ++frameIndex) {
        int frameOffset = int(frameIndex + bufferOffset);

        // do ramping every 8 samples
        if ((frameOffset & 0x7) == 0) {
            data->centerFrequencyRamp.advanceTo(_now + frameOffset);
            data->bandwidthRamp.advanceTo(_now + frameOffset);
        }

        data->_butbp0->freq = data->centerFrequencyRamp.getValue();
        data->_butbp1->freq = data->centerFrequencyRamp.getValue();
        data->_butbp0->bw = data->bandwidthRamp.getValue();
        data->_butbp1->bw = data->bandwidthRamp.getValue();

        float *tmpin[2];
        float *tmpout[2];
        for (int channel = 0; channel < _nChannels; ++channel) {
            float *in  = (float *)_inBufferListPtr->mBuffers[channel].mData  + frameOffset;
            float *out = (float *)_outBufferListPtr->mBuffers[channel].mData + frameOffset;
            if (channel < 2) {
                tmpin[channel] = in;
                tmpout[channel] = out;
            }
            if (!_playing) {
                *out = *in;
                continue;
            }

            if (channel == 0) {
                sp_butbp_compute(_sp, data->_butbp0, in, out);
            } else {
                sp_butbp_compute(_sp, data->_butbp1, in, out);
            }
        }
    }
}
