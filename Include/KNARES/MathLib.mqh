#property copyright "Copyright 2026, Dr.Kittimasak Naijit"
#property link      "https://github.com/knares-mt5"
#property strict

//+------------------------------------------------------------------+
//| KNARES Math Library - ไลบรารีคณิตศาสตร์ชั้นสูงสำหรับระบบ Quant       |
//+------------------------------------------------------------------+

/**
 * ฟังก์ชันคำนวณ Linear Regression (OLS) เพื่อหาค่า Beta และ Alpha
 * ใช้สำหรับหาความสัมพันธ์ระหว่างสองสินทรัพย์ (Hedge Ratio) ในระบบ Pair Trading
 * @param y_data อาร์เรย์ของข้อมูลตัวแปรตาม (เช่น ราคาปิดสินทรัพย์ A)
 * @param x_data อาร์เรย์ของข้อมูลตัวแปรต้น (เช่น ราคาปิดสินทรัพย์ B)
 * @param beta ตัวแปรสำหรับรับค่าความชัน (Slope) หรือ Hedge Ratio
 * @param alpha ตัวแปรสำหรับรับค่าจุดตัดแกน Y (Intercept)
 * @return true หากคำนวณสำเร็จ, false หากข้อมูลไม่เพียงพอหรือคำนวณไม่ได้
 */
bool CalculateBeta(const double &y_data[], const double &x_data[], double &beta, double &alpha)
{
   int n = ArraySize(y_data);
   // ตรวจสอบความถูกต้องของขนาดข้อมูล
   if(n != ArraySize(x_data) || n < 2) return false;

   double sum_x = 0, sum_y = 0, sum_xy = 0, sum_xx = 0;
   // สะสมค่ารวมต่างๆ ที่จำเป็นสำหรับสูตร OLS
   for(int i = 0; i < n; i++)
   {
      sum_x  += x_data[i];
      sum_y  += y_data[i];
      sum_xy += x_data[i] * y_data[i];
      sum_xx += x_data[i] * x_data[i];
   }

   // คำนวณตัวหาร (Denominator) และตรวจสอบการหารด้วยศูนย์
   double denominator = (n * sum_xx - sum_x * sum_x);
   if(MathAbs(denominator) < 1e-12) return false;

   // คำนวณค่า Beta และ Alpha ตามสูตรสถิติ
   beta = (n * sum_xy - sum_x * sum_y) / denominator;
   alpha = (sum_y - beta * sum_x) / n;

   return true;
}

/**
 * คำนวณระยะเวลาครึ่งชีวิตของการกลับเข้าหาค่าเฉลี่ย (Half-life of Mean Reversion)
 * เพื่อประเมินว่า Spread ของราคาจะใช้เวลานานเท่าใดในการกลับเข้าสู่ค่าสมดุล
 * @param spread_data อาร์เรย์ข้อมูลส่วนต่างของราคา (Spread)
 * @return จำนวนแท่งเทียนโดยประมาณในการกลับเข้าสู่ค่าเฉลี่ย, 999 หากข้อมูลไม่บ่งชี้การกลับเข้าหาค่าเฉลี่ย
 */
double CalculateHalfLife(const double &spread_data[])
{
   int n = ArraySize(spread_data);
   if(n < 3) return 999;

   // เตรียมข้อมูลสำหรับการวิเคราะห์แบบ Regression (Autoregression of differences)
   double dy[], x_lag[];
   ArrayResize(dy, n-1);
   ArrayResize(x_lag, n-1);

   for(int i=0; i<n-1; i++)
   {
      // dy คือส่วนต่างของราคาในแต่ละช่วง
      dy[i] = spread_data[i] - spread_data[i+1]; 
      // x_lag คือราคาในช่วงเวลาก่อนหน้า
      x_lag[i] = spread_data[i+1];
   }

   double lambda, alpha;
   // หาค่า Lambda (อัตราการถดถอย) ผ่านการคำนวณ Beta
   if(CalculateBeta(dy, x_lag, lambda, alpha))
   {
      // หาก lambda เป็นบวก แสดงว่าข้อมูลไม่มีแนวโน้มกลับเข้าหาค่าเฉลี่ย (Divergent)
      if(lambda >= 0) return 999;
      // สูตรการคำนวณ Half-life: ln(2) / lambda
      return -MathLog(2.0) / lambda;
   }

   return 999;
}

/**
 * คำนวณความน่าจะเป็นตามการกระจายตัวแบบปกติ (Gaussian Probability Density Function)
 * ใช้ในระบบ HMM เพื่อคำนวณหาความเป็นไปได้ที่ข้อมูลจะอยู่ในสภาวะต่างๆ
 * @param x ค่าข้อมูลที่ต้องการตรวจสอบ
 * @param mean ค่าเฉลี่ยของข้อมูล
 * @param var ค่าความแปรปรวน (Variance)
 * @return ค่าความหนาแน่นของความน่าจะเป็น (Probability Density)
 */
double GaussianPDF(double x, double mean, double var)
{
   if(var <= 0) var = 1e-9; // ป้องกันการหารด้วยศูนย์
   // สูตร Gaussian PDF: (1 / sqrt(2 * PI * var)) * exp(-(x - mean)^2 / (2 * var))
   double exponent = MathExp(-MathPow(x - mean, 2) / (2.0 * var));
   return (1.0 / MathSqrt(2.0 * M_PI * var)) * exponent;
}

/**
 * คำนวณสถิติพื้นฐาน (ค่าเฉลี่ยและส่วนเบี่ยงเบนมาตรฐาน) จากอาร์เรย์ข้อมูล
 * @param data อาร์เรย์ข้อมูล
 * @param mean ตัวแปรรับค่าเฉลี่ย
 * @param std ตัวแปรรับค่าส่วนเบี่ยงเบนมาตรฐาน
 */
void CalculateStats(const double &data[], double &mean, double &std)
{
   int n = ArraySize(data);
   if(n == 0) { mean=0; std=0; return; }
   
   // คำนวณค่าเฉลี่ย
   double sum = 0;
   for(int i=0; i<n; i++) sum += data[i];
   mean = sum / n;
   
   // คำนวณค่าความแปรปรวนและส่วนเบี่ยงเบนมาตรฐาน
   double var_sum = 0;
   for(int i=0; i<n; i++) var_sum += MathPow(data[i] - mean, 2);
   std = MathSqrt(var_sum / n);
}
