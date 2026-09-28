import torch
import torch.nn as nn
import os
import shutil

class KnaresModel(nn.Module):
    def __init__(self):
        super(KnaresModel, self).__init__()
        # 8 inputs: ADX, RSI, ATR%, EMA_diff, SMC_bias, SMC_zone, SMC_buy_q, SMC_sell_q
        # 1 output: Confidence score (0.0 to 1.0)
        self.fc = nn.Sequential(
            nn.Linear(8, 16),
            nn.ReLU(),
            nn.Linear(16, 8),
            nn.ReLU(),
            nn.Linear(8, 1),
            nn.Sigmoid()
        )

    def forward(self, x):
        return self.fc(x)

def main():
    print("Generating KNARES_Model.onnx with 8 inputs...")
    model = KnaresModel()
    model.eval()

    # Create dummy input tensor (batch_size=1, features=8)
    dummy_input = torch.randn(1, 8)
    
    onnx_filename = "KNARES_Model.onnx"
    torch.onnx.export(
        model, 
        dummy_input, 
        onnx_filename,
        export_params=True,
        opset_version=14,
        do_constant_folding=True,
        input_names=['input'], 
        output_names=['output'],
        dynamic_axes={'input': {0: 'batch_size'}, 'output': {0: 'batch_size'}}
    )
    print(f"Successfully generated {onnx_filename}.")
    
    # Define paths
    target_path = r"C:\Users\Asus\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Files\KNARES_Model.onnx"
    
    # Try to copy it to the MT5 Files directory
    try:
        os.makedirs(os.path.dirname(target_path), exist_ok=True)
        shutil.copy(onnx_filename, target_path)
        print(f"Copied ONNX model to {target_path}")
    except Exception as e:
        print(f"Could not copy to MT5 folder automatically: {e}")

if __name__ == "__main__":
    main()
